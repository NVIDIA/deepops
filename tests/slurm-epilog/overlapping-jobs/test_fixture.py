#!/usr/bin/env python3
"""Offline regression tests: real shell boundaries, only host calls replaced.

Never invokes live preflight, Slurm, account management, or firewall commands.
"""
import csv
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
DRIVER = HERE / 'run-fixture.sh'


class FixtureTests(unittest.TestCase):
    def shell(self, body, main=False):
        # Load definitions, not main; this also exercises the real option parser.
        source = DRIVER.read_text().split('\nif [ "$SELFTEST" = 1 ]; then')[0]
        with tempfile.TemporaryDirectory(dir=os.environ.get('PAPERCLIP_SCRATCH_DIR')) as tmp:
            env = dict(os.environ, TEST_TMP=tmp, FIXTURE_SOURCE=str(DRIVER))
            script = 'set --\n' + source + '\nOUT="$TEST_TMP"; CTL="$TEST_TMP"; REPORT_ENABLED=1\n' + body
            if main:
                script += "\ntrap 'rc=$?" + DRIVER.read_text().split("\ntrap 'rc=$?", 1)[1]
            return subprocess.run(['bash', '-c', script], env=env, text=True,
                                  capture_output=True, timeout=10)

    def test_submit_stdout_is_only_id(self):
        p = self.shell('as_user() { echo 123; }; id=$(submit_job qa A); printf "<%s>" "$id"')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(p.stdout, '<123>')

    def test_query_failure_is_not_job_completion(self):
        p = self.shell('sq() { return 1; }; job_is_over 123')
        self.assertNotEqual(p.returncode, 0)

    def test_requested_empty_assertions_cannot_pass(self):
        p = self.shell('SCENARIOS=1; SCEN_RAN[1]=1; write_report')
        self.assertNotEqual(p.returncode, 0, p.stdout)

    def test_incomplete_assertions_cannot_pass(self):
        p = self.shell('SCENARIOS=1; SCEN_RAN[1]=1; record 1 proc alive; write_report')
        self.assertNotEqual(p.returncode, 0, p.stdout)

    def test_missing_enroot_checks_cannot_pass(self):
        p = self.shell('SCENARIOS=1; SCEN_RAN[1]=1; record 1 ctr_dir skip; write_report')
        self.assertNotEqual(p.returncode, 0, p.stdout)

    def test_s3_report_does_not_infer_asset_survival_from_mismatch(self):
        # Literal baseline evidence: do not derive the oracle from expected_for.
        baseline = dict(ready='yes', epilog_end='yes', complete_wait='yes',
                        hook_held='yes', b_allocated_during_hold='yes',
                        proc='gone', tmp='absent', shm='absent', ctr_dir='absent',
                        ctr_runtime='absent', ctr_proc='gone', orphan='gone',
                        node_drained='no')
        survived = dict(proc='alive', tmp='present', shm='present', ctr_dir='present',
                        ctr_runtime='present', ctr_proc='alive', orphan='alive')
        cases = [
            ('all_destroyed', {}, 'MATCH', 0),
            ('only_container_directory_survived', dict(ctr_dir='present'), 'MISMATCH', 1),
            ('all_survived', survived, 'MISMATCH', 1),
            ('only_process_destroyed', dict(survived, proc='gone'), 'MISMATCH', 1),
            ('all_destroyed_but_node_drained', dict(node_drained='yes'), 'MISMATCH', 1),
        ]
        for name, overrides, verdict, rc in cases:
            with self.subTest(case=name):
                actual = dict(baseline, **overrides)
                records = '\n'.join(f'record 3 {item} {value}'
                                    for item, value in actual.items())
                p = self.shell('SCENARIOS=3; SCEN_RAN[3]=1; EXPECT=current\n' + records + '''
                    write_report; rc=$?
                    printf '%s\\n' "$(< "$OUT/report.md")"
                    printf '\\nREPORT_JSON\\n%s\\n' "$(< "$OUT/report.json")"
                    printf '\\nREPORT_TSV\\n%s\\n' "$(< "$OUT/report.tsv")"
                    exit "$rc"
                ''')
                self.assertEqual(p.returncode, rc, p.stdout + p.stderr)
                md, rest = p.stdout.split('\nREPORT_JSON\n', 1)
                raw_json, tsv = rest.split('\nREPORT_TSV\n', 1)
                report = json.loads(raw_json)
                self.assertEqual(report['overall'], verdict)
                self.assertEqual(report['scenario_verdicts'], {'3': verdict})
                self.assertEqual(report['expect'], 'current')
                rows = [dict(scenario='3', check=item, expected=baseline[item],
                             actual=value, result='MATCH' if value == baseline[item] else 'MISMATCH')
                        for item, value in actual.items()]
                self.assertEqual(report['checks'], rows)
                self.assertEqual(list(csv.DictReader(io.StringIO(tsv), delimiter='\t')), rows)
                self.assertIn(f'Overall: **{verdict}**', md)
                summary = next(line for line in md.splitlines()
                               if line.startswith("| 3 | B allocated during A's epilog |"))
                self.assertIn(f'| {verdict} |', summary)
                if verdict == 'MATCH':
                    self.assertIn("#1407 reproduced: A's epilog destroyed B's assets", summary)
                else:
                    # An aggregate mismatch (even node drain alone) cannot prove
                    # universal survival or rule out reproduction of the race.
                    self.assertNotIn('NOT reproduced', summary)
                    self.assertNotIn("B's assets survived", summary)
                    self.assertIn('review per-check results', summary)

    def test_existing_account_refused(self):
        p = self.shell('id() { echo 1000; }; ensure_user existing')
        self.assertNotEqual(p.returncode, 0)

    def test_no_teardown_before_ownership(self):
        p = self.shell('scenario_teardown() { echo MUTATED; }; write_report() { return 0; }; finalise')
        self.assertNotIn('MUTATED', p.stdout)

    def test_invalid_cli(self):
        for args in (['--scenarios', ''], ['--scenarios', '8'], ['--scenarios', '1,1'],
                     ['--user', 'root'], ['--user', 'x;id'], ['--user', 'same', '--operator', 'same'],
                     ['--no-enroot'], ['--out', '/tmp/../etc'], ['--unknown']):
            with self.subTest(args=args):
                p = subprocess.run(['bash', str(DRIVER), '--selftest', *args],
                                   capture_output=True, text=True, timeout=15)
                self.assertEqual(p.returncode, 2, p.stdout + p.stderr)

    def test_probe_stdout_is_only_cgroup(self):
        p = self.shell('''
            install_hook() { say installed; }
            remove_hooks() { say removed; }
            submit_job() { say submitted; echo 123; }
            wait_job_ready() { say ready; }
            wait_for() { return 0; }
            cleanup_user_assets() { say cleanup; }
            printf '0::/epilog-test\\n' > "$CTL/probe-epilog-123"
            value=$(probe_epilog_cgroup)
            printf '<%s>' "$value"
        ''')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(p.stdout, '<epilog-test>')

    def test_fatal_and_signal_status_survive_actual_exit_trap(self):
        for command, expected in [('die setup-failed', 2), ('kill -s INT $$', 130),
                                  ('kill -s TERM $$', 143)]:
            with self.subTest(command=command):
                p = self.shell('preflight() { ' + command + '; }; '
                               'scenario_teardown() { echo MUTATED; }', main=True)
                self.assertEqual(p.returncode, expected, p.stdout + p.stderr)
                self.assertNotIn('MUTATED', p.stdout)

    def test_scenario_7_alone_requires_v2_and_real_repeats(self):
        p = self.shell('SCENARIOS=7; SCEN_RAN[7]=1; CGROUP_MODE=v1; scenario_7; write_report')
        self.assertEqual(p.returncode, 3, p.stdout + p.stderr)
        p = self.shell('''
            SCENARIOS=7; SCEN_RAN[7]=1; CGROUP_MODE=v2
            scenario_1_2() { :; }; scenario_4() { :; }
            scenario_teardown() { :; }
            scenario_7; write_report
        ''')
        self.assertEqual(p.returncode, 3, p.stdout + p.stderr)

    def test_import_failure_does_not_enable_enroot(self):
        p = self.shell('STAGE="$TEST_TMP"; as_user() { return 1; }; import_image')
        self.assertNotEqual(p.returncode, 0)

    def test_no_epilog_end_does_not_record_success(self):
        p = self.shell('''
            CURRENT_SCENARIO=1; SCENARIOS=1; SCEN_RAN[1]=1
            for item in $(required_checks 1); do
                [ "$item" = epilog_end ] || record 1 "$item" "$(expected_for 1 "$item")"
            done
            WAIT_EPILOG=0; epilog_journal() { echo 'START user=qa job=123'; }
            wait_epilog_end 0 qa 123 || :
            write_report
        ''')
        self.assertEqual(p.returncode, 3, p.stdout + p.stderr)

    def test_complete_assertion_set_can_pass(self):
        p = self.shell('''
            SCENARIOS=1; SCEN_RAN[1]=1
            for item in $(required_checks 1); do record 1 "$item" "$(expected_for 1 "$item")"; done
            write_report
        ''')
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)

    def test_one_skipped_mandatory_assertion_invalidates_full_set(self):
        p = self.shell('''
            SCENARIOS=1; SCEN_RAN[1]=1
            for item in $(required_checks 1); do
                value=$(expected_for 1 "$item"); [ "$item" != ctr_proc ] || value=skip
                record 1 "$item" "$value"
            done
            write_report
        ''')
        self.assertEqual(p.returncode, 3, p.stdout + p.stderr)

    def test_existing_hook_not_overwritten(self):
        p = self.shell('''
            EPILOG_DIR="$TEST_TMP"; echo original > "$EPILOG_DIR/10-fixture-hold"
            if install_hook /absent/10-fixture-hold; then exit 1; fi
            printf '<%s>' "$(< "$EPILOG_DIR/10-fixture-hold")"
        ''')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(p.stdout, '<original>')

    def test_only_tracked_job_ids_are_cancelled(self):
        p = self.shell('''
            printf '123\\tqa\\towned\\n456\\tops\\towned\\n' > "$CTL/jobs"
            SBIN="$TEST_TMP"
            printf '#!/bin/bash\\nprintf "cancel:<%%s>\\\\n" "$*"\\n' > "$SBIN/scancel"
            chmod +x "$SBIN/scancel"
            job_is_over() { return 1; }; wait_for() { return 0; }
            drain_user_jobs qa
        ''')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(p.stdout, 'cancel:<123>\n')

    def test_actual_job_rejects_enroot_create_and_start_failures(self):
        # Only remap asset roots; execute the actual job readiness logic. The
        # enroot command is the unavailable external dependency, not the logic.
        for fail_at in ('create', 'start'):
            with self.subTest(fail_at=fail_at), tempfile.TemporaryDirectory(
                    dir=os.environ.get('PAPERCLIP_SCRATCH_DIR')) as tmp:
                root = Path(tmp)
                for name in ('bin', 'ctl', 'status', 'tmp', 'shm'):
                    (root / name).mkdir()
                stub = root / 'bin/enroot'
                stub.write_text('#!/bin/bash\n[ "$1" != "' + fail_at + '" ]\n')
                stub.chmod(0o755)
                job = (HERE / 'jobs/fixture-job.sh').read_text()
                job = job.replace('/tmp/epilog-fixture-', str(root / 'tmp/epilog-fixture-'))
                job = job.replace('/dev/shm/epilog-fixture-', str(root / 'shm/epilog-fixture-'))
                (root / 'job.sh').write_text(job)
                (root / 'image.sqsh').write_text('offline-image-placeholder')
                env = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'])
                p = subprocess.run(['bash', str(root / 'job.sh'), 'offline-test',
                                    str(root / 'ctl'), str(root / 'image.sqsh'), str(root / 'status')],
                                   env=env, capture_output=True, text=True, timeout=5)
                self.assertEqual(p.returncode, 2, p.stdout + p.stderr)
                self.assertFalse((root / 'status/ready-offline-test').exists())
                self.assertEqual((root / 'status/enroot-status-offline-test').read_text().strip(),
                                 fail_at + '-failed')

    def test_failed_enroot_status_rejects_otherwise_ready_assets(self):
        p = self.shell('''
            BASE="$TEST_TMP"; RUN_KEY=offline; USER_QA=qa
            mkdir "$BASE/status-qa"
            echo start-failed > "$BASE/status-qa/enroot-status-offline-A"
            obs_proc() { echo alive; }; ctr_dir_for() { echo "$TEST_TMP"; }
            precheck_job_assets qa A
        ''')
        self.assertNotEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertIn('enroot-ready', p.stderr)

    def test_completed_ids_are_retired_only_after_successful_teardown(self):
        p = self.shell('''
            OWNS_SETUP=1; USER_QA=qa; USER_OPS=ops
            printf '123\\tqa\\towned\\n' > "$CTL/jobs"
            drain_user_jobs() { return 0; }; remove_hooks() { return 0; }
            cleanup_user_assets() { return 0; }
            scenario_teardown || exit 1
            [ ! -s "$CTL/jobs" ]
        ''')
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)

    def test_setup_logging_does_not_modify_unowned_output(self):
        p = self.shell('REPORT_ENABLED=0; say refusing-output; [ ! -e "$OUT/driver.log" ]')
        self.assertEqual(p.returncode, 0, p.stderr)

    def test_uid_zero_alias_refused(self):
        p = self.shell('id() { echo 0; }; ensure_user root_alias')
        self.assertNotEqual(p.returncode, 0)

    def test_failed_namespace_injector_never_falls_back_to_real_epilog(self):
        with tempfile.TemporaryDirectory(dir=os.environ.get('PAPERCLIP_SCRATCH_DIR')) as tmp:
            root = Path(tmp)
            active = root / 'active'
            ctl = root / 'state/epilog-fixture-abcdef123456/ctl'
            active.mkdir(); ctl.mkdir(parents=True); (root / 'bin').mkdir()
            (active / 'control-path').write_text(str(ctl))
            (ctl / 'fault-123').touch()
            for name, body in {'stat': 'case "$2" in %u) echo 0;; %a) echo 755;; esac',
                               'unshare': 'exit 1'}.items():
                stub = root / 'bin' / name
                stub.write_text('#!/bin/bash\n' + body + '\n'); stub.chmod(0o755)
            epilog = root / 'product-epilog'
            epilog.write_text('#!/bin/bash\necho UNSAFE_FALLBACK\n'); epilog.chmod(0o755)
            wrapper = (HERE / 'epilog-wrapper.sh').read_text()
            wrapper = wrapper.replace('/run/deepops-epilog-fixture', str(active))
            wrapper = wrapper.replace('/var/lib', str(root / 'state'))
            wrapper = wrapper.replace('/etc/slurm/epilog.sh', str(epilog))
            (root / 'wrapper').write_text(wrapper)
            env = dict(os.environ, PATH=str(root / 'bin') + ':' + os.environ['PATH'], SLURM_JOB_ID='123')
            p = subprocess.run(['bash', str(root / 'wrapper')], env=env,
                               text=True, capture_output=True, timeout=5)
            self.assertEqual(p.returncode, 0, p.stderr)  # injector must not drain
            self.assertEqual((ctl / 'fault-done-123').read_text().strip(), '1')
            self.assertFalse((ctl / 'fault-isolated-123').exists())
            self.assertNotIn('UNSAFE_FALLBACK', p.stdout + (ctl / 'fault-log-123').read_text())

    def test_enroot_existing_or_shared_paths_are_refused(self):
        p = self.shell('''
            enroot_data_path_for() { echo "$TEST_TMP"; }
            enroot_runtime_path_for() { echo "$TEST_TMP/new-runtime"; }
            reserve_enroot_paths qa
        ''')
        self.assertNotEqual(p.returncode, 0)
        p = self.shell('''
            ENROOT_DATA[ops]="$TEST_TMP/shared"
            enroot_data_path_for() { echo "$TEST_TMP/shared/qa"; }
            enroot_runtime_path_for() { echo "$TEST_TMP/new-runtime"; }
            reserve_enroot_paths qa
        ''')
        self.assertNotEqual(p.returncode, 0)

    def test_partial_output_from_failed_state_query_is_not_success(self):
        p = self.shell('sq() { echo RUNNING; return 1; }; job_is_running 123')
        self.assertEqual(p.returncode, 2)

    def test_untracked_jobs_prevent_account_asset_teardown(self):
        p = self.shell('''
            OWNS_SETUP=1; CREATED_USERS=(qa); USER_QA=qa; USER_OPS=ops
            : > "$CTL/jobs"
            drain_user_jobs() { return 0; }; sq() { echo 999; }
            cleanup_user_assets() { echo UNSAFE_CLEANUP; }
            scenario_teardown
        ''')
        self.assertNotEqual(p.returncode, 0)
        self.assertNotIn('UNSAFE_CLEANUP', p.stdout)

    def test_report_write_failure_is_error(self):
        p = self.shell('OUT="$TEST_TMP/absent"; write_report')
        self.assertEqual(p.returncode, 2)

    def test_missing_option_values(self):
        for flag in ('--expect', '--scenarios', '--out', '--node', '--slurm-prefix',
                     '--user', '--operator', '--image'):
            with self.subTest(flag=flag):
                p = subprocess.run(['bash', str(DRIVER), flag], capture_output=True,
                                   text=True, timeout=3)
                self.assertEqual(p.returncode, 2, p.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
