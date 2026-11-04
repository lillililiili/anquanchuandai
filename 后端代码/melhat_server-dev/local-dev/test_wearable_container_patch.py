import copy
import importlib.util
import pathlib
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('container_patch', pathlib.Path(__file__).with_name('wearable-container-patch.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CompatiblePatchTests(unittest.TestCase):
    def test_docker_cli_can_be_selected_without_changing_path(self):
        executable = 'C:/Program Files/Docker/Docker/resources/bin/docker.exe'
        with patch.dict(module.os.environ, {'MELHAT_DOCKER_CLI': executable}), \
             patch.object(module.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, b'ok')) as run:
            self.assertEqual(module.docker('version'), b'ok')
            self.assertEqual(run.call_args.args[0], [executable, 'version'])

    def test_anonymous_health_uses_read_only_root_and_requires_protected_requests_to_reject(self):
        with patch.object(module, 'docker', side_effect=[b'welcome\n200', b'401', b'401']) as docker:
            self.assertEqual(module.anonymous_health(), {
                '/api/admin/v1/state': 401,
                '/api/guardian/v1/mobile/context?siteId=site-1': 401})
            self.assertEqual(docker.call_args_list[0].args[-1], 'http://127.0.0.1:18084/')
            self.assertNotIn('captchaImage', str(docker.call_args_list))
        with patch.object(module, 'docker', side_effect=[b'welcome\n200', b'200']):
            with self.assertRaisesRegex(RuntimeError, 'did not require authentication'):
                module.anonymous_health()

    def test_anonymous_health_rejects_empty_body_redirect_and_malformed_response(self):
        for response in (b'\n200', b' \n200', b'welcome\n302', b'welcome\n204', b'welcome'):
            with self.subTest(response=response), \
                 patch.object(module, 'docker', return_value=response) as docker, \
                 patch.object(module.time, 'monotonic', side_effect=[0, 1, 101]), \
                 patch.object(module.time, 'sleep'):
                with self.assertRaisesRegex(RuntimeError, 'Anonymous backend health did not pass'):
                    module.anonymous_health()
                docker.assert_called_once()

    def baseline(self):
        return {'mode': 'ACTIVE', 'namespaces': 'guardian,media', 'watchVisible': True,
                'dataVersion': 'wearable-clean-v1', 'inventory': 'RL-W001,device-12,device-13',
                'activeAssignments': 'assignment-23|device-12|person-test|1,assignment-26|device-13|person-test|1',
                'reportWatermark': 80, 'pendingReports': 2,
                'counts': {table: 5 for table in module.STABLE_TABLES + module.HISTORY_TABLES}}

    def test_reads_reject_database_mutations_and_stacked_statements(self):
        with patch.object(module, 'docker') as docker:
            for statement in ('UPDATE wearable_runtime_control SET mode=\'ACTIVE\'',
                              'SELECT 1; DELETE FROM wearable_event', 'DROP TABLE wearable_location'):
                with self.assertRaises(RuntimeError):
                    module.read_sql(statement)
            docker.assert_not_called()

    def test_checks_allow_new_history_and_drained_reports_without_losing_old_rows(self):
        before = self.baseline()
        after = copy.deepcopy(before)
        after.update(reportWatermark=83, pendingReports=0)
        for table in module.HISTORY_TABLES:
            after['counts'][table] += 3
        module.verify_preservation(before, after)
        after['counts']['wearable_location'] = 4
        with self.assertRaisesRegex(RuntimeError, 'history count decreased'):
            module.verify_preservation(before, after)

    def test_checks_reject_watch_inventory_and_watermark_regressions(self):
        before = self.baseline()
        for key, changed in (('watchVisible', False), ('inventory', 'device-12'),
                             ('reportWatermark', 79), ('mode', 'PAUSED'), ('activeAssignments', 'changed-binding')):
            after = copy.deepcopy(before)
            after[key] = changed
            with self.assertRaises(RuntimeError):
                module.verify_preservation(before, after)

    def test_work_history_and_initial_enabled_migration_are_preserved(self):
        before=self.baseline();after=copy.deepcopy(before);after['workBusinessEnabled']=True
        module.verify_preservation(before,after)
        after['workBusinessEnabled']=False
        with self.assertRaisesRegex(RuntimeError,'default to enabled'):module.verify_preservation(before,after)
        before['workBusinessEnabled']=False;after['workBusinessEnabled']=True
        with self.assertRaisesRegex(RuntimeError,'work business setting changed'):module.verify_preservation(before,after)
        after['workBusinessEnabled']=False;after['counts']['wearable_work']-=1
        with self.assertRaisesRegex(RuntimeError,'history count decreased'):module.verify_preservation(before,after)

    def test_runtime_preserves_opaque_settings_mounts_ports_network(self):
        previous = {'Config': {'Env': ['UNCHANGED_SETTING=value', 'OPAQUE_KEY=retain'], 'Cmd': ['--server.port=18084'],
                               'Labels': {'owned': 'yes'}, 'User': '', 'WorkingDir': '/app'},
                    'HostConfig': {'RestartPolicy': {'Name': 'unless-stopped'},
                                   'PortBindings': {'18084/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '18084'}]},
                                   'ExtraHosts': ['local-service:host-gateway']},
                    'NetworkSettings': {'Networks': {'existing-network': {}}},
                    'Mounts': [{'Type': 'volume', 'Name': 'existing-data', 'Destination': '/data', 'RW': True}]}
        args = module.recreate_args(previous, 'new-image')
        for expected in ('UNCHANGED_SETTING=value', 'OPAQUE_KEY=retain', 'existing-data:/data',
                         '127.0.0.1:18084:18084/tcp', 'existing-network', 'local-service:host-gateway'):
            self.assertIn(expected, args)
        self.assertEqual(args[-2:], ['new-image', '--server.port=18084'])

    def test_failed_partial_start_keeps_failed_container_and_restores_current_sql_writer(self):
        previous = {'Id': 'previous-id'}
        with patch.object(module, 'inspect', side_effect=[{'Id': 'partially-created'}, {'Id': 'previous-id'}]), \
             patch.object(module, 'docker') as docker, patch.object(module, 'anonymous_health') as health:
            module.restore_compatible(previous, 'retained-name', 'failed-name')
            self.assertEqual([call.args for call in docker.call_args_list], [
                ('stop', '--time', '30', module.LIVE), ('rename', module.LIVE, 'failed-name'),
                ('rename', 'retained-name', module.LIVE), ('start', module.LIVE)])
            health.assert_called_once()

    def test_failure_before_rename_restarts_same_container_without_any_restore(self):
        with patch.object(module, 'inspect', return_value={'Id': 'previous-id'}), \
             patch.object(module, 'docker') as docker, patch.object(module, 'anonymous_health'):
            module.restore_compatible({'Id': 'previous-id'}, 'retained-name', 'failed-name')
            docker.assert_called_once_with('start', module.LIVE)

    def test_timeout_does_not_print_opaque_deployment_arguments(self):
        with patch.object(module.subprocess, 'run', side_effect=subprocess.TimeoutExpired(['docker', '-e', 'OPAQUE=do-not-print'], 1)):
            with self.assertRaises(RuntimeError) as caught:
                module.docker('run', '-e', 'OPAQUE=do-not-print')
            self.assertNotIn('do-not-print', str(caught.exception))
            self.assertEqual(str(caught.exception), 'Docker operation timed out: run')

    def test_backup_disk_failure_cannot_skip_service_recovery(self):
        record = {}
        with patch.object(module, 'write_json', side_effect=OSError('disk full')), \
             patch.object(module, 'restore_compatible') as restore, patch.object(module, 'snapshot', return_value=self.baseline()):
            module.recover_after_failure({'Id': 'old'}, 'retained', 'failed', pathlib.Path('ignored-output'), record, OSError('disk full'))
            restore.assert_called_once_with({'Id': 'old'}, 'retained', 'failed')
            self.assertEqual(record['status'], 'compatible-predecessor-restored')

    def test_unreviewed_security_or_extra_storage_is_rejected_before_stopping(self):
        standard = {'Id': '123456789012abcdef', 'Config': {'Hostname': '123456789012'},
                    'HostConfig': {}, 'Mounts': [{'Destination': '/data'}],
                    'NetworkSettings': {'Networks': {'daily': {}}}}
        module.require_standard_deployment(standard)
        protected = copy.deepcopy(standard)
        protected['HostConfig']['ReadonlyRootfs'] = True
        with self.assertRaisesRegex(RuntimeError, 'ReadonlyRootfs'):
            module.require_standard_deployment(protected)
        protected = copy.deepcopy(standard)
        protected['Mounts'].append({'Destination': '/configuration'})
        with self.assertRaisesRegex(RuntimeError, 'outside /data'):
            module.require_standard_deployment(protected)

    def test_only_known_readonly_configuration_mount_is_preserved(self):
        standard = {'Id': '123456789012abcdef', 'Config': {'Hostname': '123456789012'},
                    'HostConfig': {}, 'Mounts': [{'Destination': '/run/secrets/fuda-api.yml', 'Type': 'bind', 'RW': False}],
                    'NetworkSettings': {'Networks': {'daily': {}}}}
        module.require_standard_deployment(standard)
        for changed in ({'RW': True}, {'Type': 'volume'}, {'Destination': '/run/secrets/unknown.yml'}):
            altered = copy.deepcopy(standard)
            altered['Mounts'][0].update(changed)
            with self.assertRaisesRegex(RuntimeError, 'outside /data'):
                module.require_standard_deployment(altered)


if __name__ == '__main__':
    unittest.main()
