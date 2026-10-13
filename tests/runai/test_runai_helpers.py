import importlib.util
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


filters = load("roles/runai/filter_plugins/runai.py", "runai_filters")
api = load("roles/runai/files/runai_api.py", "runai_api")


class TestFilters(unittest.TestCase):
    def test_deep_merge_replaces_scalars_and_merges_dicts(self):
        base = {"a": {"b": 1, "c": 2}, "d": [1]}
        self.assertEqual(filters.runai_deep_merge(base, {"a": {"b": 9}, "d": [2]}),
                         {"a": {"b": 9, "c": 2}, "d": [2]})
        self.assertEqual(base["a"]["b"], 1)  # inputs untouched

    def test_password_policy(self):
        ok = filters.runai_password_ok
        self.assertTrue(ok("Passw0rd!x"))
        for bad in ("shrt1A!", "nouppercase1!", "NOLOWERCASE1!", "NoDigits!!", "NoSpecial11A", "", None, 5):
            self.assertFalse(ok(bad), bad)


class TestKubeParsers(unittest.TestCase):
    NODES = {"items": [
        {"metadata": {"labels": {"nvidia.com/gpu.present": "true", "nvidia.com/cuda.driver-version.major": "615"}},
         "status": {"allocatable": {"nvidia.com/gpu": "2"}}},
        {"metadata": {"labels": {}}, "status": {"allocatable": {}}},
        {"metadata": {"labels": {"nvidia.com/gpu.present": "true"}}, "status": {"allocatable": {"nvidia.com/gpu": "x"}}},
    ]}

    def test_gpu_count_ignores_bad_values(self):
        self.assertEqual(filters.runai_gpu_count(self.NODES), 2)
        self.assertEqual(filters.runai_gpu_count({"items": []}), 0)

    def test_driver_majors_only_gpu_nodes(self):
        self.assertEqual(filters.runai_driver_majors(self.NODES), [615, 0])

    def test_default_storageclass(self):
        doc = {"items": [
            {"metadata": {"name": "a", "annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}},
            {"metadata": {"name": "b"}}]}
        self.assertEqual(filters.runai_default_storageclasses(doc), ["a"])
        self.assertEqual(filters.runai_default_storageclasses(json_text(doc)), ["a"])


def json_text(doc):
    import json
    return json.dumps(doc)


class TestInstallString(unittest.TestCase):
    TEXT = ("helm upgrade -i runai-cluster runai/runai-cluster -n runai \\\n"
            "  --set controlPlane.url=runai.lab.test \\\n"
            "  --set controlPlane.bootstrapToken=abc.def \\\n"
            "  --set cluster.uid=1234-5678 \\\n"
            "  --set cluster.url=\"https://runai.lab.test\" --version=\"3.0.20\" --create-namespace")

    def test_parse_and_nest(self):
        pairs = api.parse_set_args(self.TEXT)
        self.assertEqual(pairs["controlPlane.url"], "runai.lab.test")
        self.assertEqual(pairs["cluster.url"], "https://runai.lab.test")
        self.assertEqual(api.nest(pairs)["cluster"]["uid"], "1234-5678")

    def test_indexed_keys(self):
        self.assertEqual(api.nest({"global.imagePullSecrets[0].name": "x"}),
                         {"global": {"imagePullSecrets": [{"name": "x"}]}})

    def test_bad_key_rejected(self):
        with self.assertRaises(api.ApiError):
            api.nest({"a b": "x"})


if __name__ == "__main__":
    unittest.main()
