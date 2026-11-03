"""Regressions for ownership, uninstall verification and exposure identity."""
import unittest
from unittest.mock import patch
from test_runai import vr, args, FakeKube

NODES = {'items': [{'status': {'addresses': [{'type': 'InternalIP', 'address': '192.0.2.10'}]}}]}


class Regressions(unittest.TestCase):
    def test_no_ingress_service_does_not_claim_node(self):
        self.assertEqual(vr.ingress_addresses({'items': []}, NODES), set())

    def test_loadbalancer_does_not_claim_node(self):
        svc = {'items': [{'spec': {'type': 'LoadBalancer'}, 'status': {'loadBalancer': {'ingress': [{'ip': '192.0.2.60'}]}}}]}
        self.assertEqual(vr.ingress_addresses(svc, NODES), {'192.0.2.60'})

    def exposure(self, routes):
        class K(FakeKube):
            def get_json(self, cmd, timeout=60):
                if 'gateways.gateway.networking.k8s.io' in cmd:
                    return {'items': [{'metadata': {'name': 'unrelated', 'namespace': 'other'}, 'status': {'addresses': [{'value': '192.0.2.10'}]}}]}, ''
                if 'ingresses' in cmd:
                    return {'items': routes}, ''
                if 'httproutes.gateway.networking.k8s.io' in cmd:
                    return {'items': []}, ''
                if 'services' in cmd:
                    return {'items': [{'spec': {'type': 'NodePort'}}]}, ''
                if cmd == ['get', 'nodes']:
                    return NODES, ''
                return super().get_json(cmd, timeout)
        result = vr.new_result('platform')
        vr.check_exposure(K(), result, args('--mode', 'platform', '--platform-domain', 'runai.example', '--skip-gpu-jobs', '--resolve-ip', '192.0.2.10', '--exposure', 'ingress'))
        return result

    def test_unrelated_gateway_cannot_override_runai_ingress(self):
        r = self.exposure([{'spec': {'rules': [{'host': 'runai.example'}]}}])
        self.assertEqual(r['exposure_reached'], 'ingress')
        self.assertEqual(r['failures'], [])

    def test_missing_runai_routes_cannot_prove_ingress(self):
        r = self.exposure([])
        self.assertEqual(r['exposure_reached'], 'unknown')
        self.assertTrue(r['failures'])

    def test_uninstall_detects_owned_gateway_artifacts(self):
        class K(FakeKube):
            def get_json(self, cmd, timeout=60):
                if cmd == ['get', 'crd']:
                    return {'items': [{'metadata': {'name': 'gateways.gateway.networking.k8s.io', 'annotations': {'deepops.nvidia.com/runai-installed': 'true'}}}]}, ''
                if 'configmaps' in cmd:
                    return {'items': [{'metadata': {'name': 'deepops-runai-kgateway', 'namespace': 'kgateway-system'}}]}, ''
                return super().get_json(cmd, timeout)
        with patch.object(vr, 'run', return_value=(0, '[]', '')):
            r = vr.validate(args('--verify-uninstalled'), {}, K())
        self.assertFalse(r['ok'])
        self.assertIn('crd/gateways.gateway.networking.k8s.io', r['leftovers'])
        self.assertIn('release-owner/kgateway-system/deepops-runai-kgateway', r['leftovers'])

    def test_uninstall_helm_failure_is_not_clean(self):
        with patch.object(vr, 'run', return_value=(1, '', 'denied')):
            self.assertFalse(vr.validate(args('--verify-uninstalled'), {}, FakeKube())['ok'])
