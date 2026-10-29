import copy
from contextlib import ExitStack
from email.message import Message
import errno
import importlib.util
import io
import json
import pathlib
import subprocess
import tempfile
import unittest
import urllib.error
import urllib.response
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location('ttl_patch', pathlib.Path(__file__).with_name('patch-playback-ttl-v6.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PlaybackPatchTests(unittest.TestCase):
    OPTIONAL_HOST_LISTS = {
        'BlkioDeviceReadBps', 'BlkioDeviceReadIOps', 'BlkioDeviceWriteBps',
        'BlkioDeviceWriteIOps', 'BlkioWeightDevice', 'Devices', 'Dns',
        'DnsOptions', 'DnsSearch', 'ExtraHosts', 'Ulimits',
    }

    def deployment(self, cgroup='host'):
        identity = 'a' * 64
        return {
            'Id': identity, 'Name': '/helmet-media-control-1', 'Image': 'sha256:existing',
            'State': {'Running': True, 'Status': 'running'},
            'Config': {'Image': 'helmet-media-control:protocol-20261026', 'Hostname': identity[:12],
                       'Cmd': ['node', 'server.mjs'], 'Entrypoint': None, 'Healthcheck': None,
                       'Labels': {'com.docker.compose.project': 'helmet-media'},
                       'User': '', 'WorkingDir': '/app', 'AttachStdout': False, 'AttachStderr': False,
                       'Env': ['MEDIA_PUBLIC_IP=39.106.212.138',
                               'MEDIA_PUBLIC_ORIGIN=https://lingzhiaide.com', 'OPAQUE=test-secret-do-not-print']},
            'HostConfig': {'NetworkMode': 'host', 'IpcMode': 'private', 'CgroupnsMode': cgroup,
                           'RestartPolicy': {'Name': 'unless-stopped'},
                           'LogConfig': {'Type': 'json-file', 'Config': {}}, 'PidsLimit': -1, 'CpuQuota': 0,
                           'CapDrop': ['ALL'], 'SecurityOpt': ['no-new-privileges:true'],
                           'MaskedPaths': list(module.MASKED_DEFAULTS),
                           'ReadonlyPaths': list(module.READONLY_DEFAULTS)},
            'Mounts': [{'Type': 'bind', 'Source': str(module.ROOT / '.local/data'),
                        'Destination': '/data', 'RW': True, 'Propagation': 'rprivate'}]}

    def test_observed_namespaces_are_preserved_explicitly(self):
        for cgroup in ('private', 'host'):
            with self.subTest(cgroup=cgroup):
                previous = self.deployment(cgroup)
                module.validate_configuration(previous)
                args = module.run_args(previous, 'sha256:new', '/private/container.env')
                self.assertEqual(args[args.index('--ipc') + 1], 'private')
                self.assertEqual(args[args.index('--cgroupns') + 1], cgroup)
                self.assertEqual(args.count('--ipc'), 1)
                self.assertEqual(args.count('--cgroupns'), 1)
                module.verify_configuration(previous, copy.deepcopy(previous))

    def test_unknown_or_implicit_namespaces_cannot_recreate_container(self):
        cases = [('IpcMode', value) for value in (None, '', 'host', 'none', 'shareable', 'container:other')]
        cases += [('CgroupnsMode', value) for value in (None, '', 'unknown', 'container:other')]
        for key, value in cases:
            with self.subTest(key=key, value=value):
                previous = self.deployment()
                previous['HostConfig'][key] = value
                with self.assertRaisesRegex(RuntimeError, 'Unexpected namespaces:') as error:
                    module.validate_configuration(previous)
                self.assertIn(key + '=' + repr(value), str(error.exception))
                with self.assertRaises(RuntimeError):
                    module.run_args(previous, 'sha256:new', '/private/container.env')

    def test_replacement_namespace_changes_are_rejected(self):
        previous = self.deployment()
        for key, changed in (('IpcMode', 'host'), ('CgroupnsMode', 'private')):
            current = copy.deepcopy(previous)
            current['HostConfig'][key] = changed
            with self.assertRaisesRegex(RuntimeError, key):
                module.verify_configuration(previous, current)

    def test_only_reviewed_image_tags_are_accepted(self):
        for tag in ('helmet-media-control:1', 'helmet-media-control:protocol-20261026'):
            previous = self.deployment()
            previous['Config']['Image'] = tag
            module.validate_configuration(previous)
        previous['Config']['Image'] = 'unreviewed-control:latest'
        with self.assertRaisesRegex(RuntimeError, 'reviewed control image tag'):
            module.validate_configuration(previous)

    def test_only_two_expected_ttl_fragments_change_and_publish_is_preserved(self):
        source = (module.OLD_TOKEN + ", publish=this.token('publish', stream.streamId, 14400);\n" + module.OLD_EXPIRY).encode()
        result = module.updated_source(source)
        self.assertIn(module.NEW_TOKEN.encode(), result)
        self.assertIn(module.NEW_EXPIRY.encode(), result)
        self.assertIn(b"this.token('publish', stream.streamId, 14400)", result)
        self.assertEqual(result.replace(module.NEW_TOKEN.encode(), module.OLD_TOKEN.encode()).replace(module.NEW_EXPIRY.encode(), module.OLD_EXPIRY.encode()), source)

    def test_unexpected_already_patched_or_duplicate_source_is_rejected(self):
        for value in (module.NEW_TOKEN + module.NEW_EXPIRY, module.OLD_TOKEN * 2 + module.OLD_EXPIRY, module.OLD_TOKEN):
            with self.assertRaises(RuntimeError):
                module.updated_source(value.encode())

    def test_recording_guard_includes_start_and_finalization(self):
        value = b'{"sequence":8,"recordings":{"a":{"status":"starting"},"b":{"status":"recording"},"c":{"status":"finalizing"},"d":{"status":"ready"}}}'
        self.assertEqual(module.state_summary(value)['activeRecordings'], 3)

    def test_docker_timeout_never_discloses_opaque_environment(self):
        with patch.object(module.subprocess, 'run', side_effect=subprocess.TimeoutExpired(['docker', '-e', 'KEY=private'], 1)):
            with self.assertRaises(RuntimeError) as caught:
                module.docker('run', '-e', 'KEY=private')
            self.assertNotIn('private', str(caught.exception))

    def test_configuration_diff_rejects_mount_and_secret_changes(self):
        previous = self.deployment()
        module.verify_configuration(previous, copy.deepcopy(previous))
        for changed in ('env', 'mount'):
            current = copy.deepcopy(previous)
            if changed == 'env':
                current['Config']['Env'] = ['OPAQUE=changed']
            else:
                current['Mounts'][0]['Source'] = '/different/data'
            with self.assertRaises(RuntimeError):
                module.verify_configuration(previous, current)

    def test_restore_reuses_current_data_and_retained_container(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / 'service-before.mjs').write_bytes(b'old source')
            (root / 'state.json').write_bytes(b'new events must survive')
            record = {'container': 'control', 'retainedContainer': 'old-control', 'failedContainer': 'failed-control', 'candidateId': 'new-id'}
            previous = {'Id': 'old-id', 'Image': 'old-image', 'Config': {'Image': 'control:1'}}
            with patch.object(module, 'ROOT', root), \
                 patch.object(module, 'inspect', side_effect=[{'Id': 'new-id', 'State': {'Running': True}}, {'Id': 'old-id'}]), \
                 patch.object(module, 'docker') as docker, patch.object(module, 'healthy'):
                module.restore(previous, root, record)
                self.assertEqual((root / 'state.json').read_bytes(), b'new events must survive')
                self.assertEqual([call.args for call in docker.call_args_list], [
                    ('stop', '--time', '30', 'new-id'), ('rename', 'new-id', 'failed-control'),
                    ('rename', 'old-id', 'control'), ('start', 'old-id'), ('tag', 'old-image', 'control:1')])

    def test_host_source_disk_failure_does_not_prevent_predecessor_start(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / 'service-before.mjs').write_bytes(b'old source')
            record = {'container': 'control', 'retainedContainer': 'old-control', 'failedContainer': 'failed-control'}
            previous = {'Id': 'old-id', 'Image': 'old-image', 'Config': {'Image': 'control:1'}}
            with patch.object(module, 'ROOT', root), patch.object(module, 'inspect', return_value={'Id': 'old-id'}), \
                 patch.object(module, 'docker') as docker, patch.object(module, 'healthy') as healthy, \
                 patch.object(pathlib.Path, 'write_bytes', side_effect=OSError('disk full')):
                module.restore(previous, root, record)
                self.assertEqual(docker.call_args_list[0].args, ('start', 'old-id'))
                healthy.assert_called_once_with(previous)
                self.assertFalse(record['recoverySourceRestored'])

    @staticmethod
    def local_private_write(path, value):
        # Unit tests use only dummy values and portable temp files. The Linux
        # deployment writer's O_NOFOLLOW implementation is not replaced in use.
        if not isinstance(value, bytes):
            value = json.dumps(value, sort_keys=True).encode('utf-8')
        pathlib.Path(path).write_bytes(value)

    def stopped_candidate(self, previous, image='sha256:candidate', candidate_id=None):
        value = copy.deepcopy(previous)
        value.update(Id=candidate_id or 'b' * 64, Image=image,
                     Name='/control-candidate', State={'Running': False, 'Status': 'created'})
        value['Config'].update(Image=image)
        return value

    def test_custom_hostname_and_domain_are_explicitly_preserved(self):
        for hostname, domain in (('existing-media-control', 'internal.example'), ('existing-media-control', ''), ('a' * 12, '')):
            with self.subTest(hostname=hostname, domain=domain):
                previous = self.deployment()
                previous['Config'].update(Hostname=hostname, Domainname=domain)
                module.validate_configuration(previous)
                self.assertEqual(module.host_identity(previous), {'Hostname': hostname, 'Domainname': domain})
                args = module.create_args(previous, 'sha256:candidate', 'candidate-only', '/private/container.env')
                self.assertEqual(args[args.index('--hostname') + 1], hostname)
                self.assertEqual(args.count('--hostname'), 1)
                if domain:
                    self.assertEqual(args[args.index('--domainname') + 1], domain)
                    self.assertEqual(args.count('--domainname'), 1)
                else:
                    self.assertNotIn('--domainname', args)
                candidate = self.stopped_candidate(previous)
                module.verify_stopped_candidate(previous, candidate, 'sha256:candidate', 'b' * 64)

    def test_candidate_hostname_or_domain_change_is_rejected(self):
        previous = self.deployment()
        previous['Config'].update(Hostname='existing-control', Domainname='internal.example')
        for key in ('Hostname', 'Domainname'):
            for value in ('changed.example', '', None):
                with self.subTest(key=key, value=value):
                    current = self.stopped_candidate(previous)
                    current['Config'][key] = value
                    with self.assertRaisesRegex(RuntimeError, 'Config.' + key):
                        module.verify_stopped_candidate(previous, current, 'sha256:candidate', 'b' * 64)

    def test_missing_empty_or_invalid_explicit_host_identity_is_rejected(self):
        for key, values in (('Hostname', (None, '', 42, 'bad\nname', 'bad\x00name', 'bad\x7fname')),
                            ('Domainname', (None, 42, 'bad\rname', 'bad\x7fname'))):
            for value in values:
                with self.subTest(key=key, value=value):
                    previous = self.deployment()
                    previous['Config'][key] = value
                    with self.assertRaisesRegex(RuntimeError, key):
                        module.validate_configuration(previous)
                    with self.assertRaisesRegex(RuntimeError, key):
                        module.create_args(previous, 'sha256:candidate', 'candidate-only', '/private/container.env')
        previous = self.deployment()
        previous['Config'].pop('Hostname')
        with self.assertRaisesRegex(RuntimeError, 'Hostname'):
            module.validate_configuration(previous)
        with self.assertRaisesRegex(RuntimeError, 'Hostname'):
            module.create_args(previous, 'sha256:candidate', 'candidate-only', '/private/container.env')

    def test_docker_version_path_sets_are_accepted_without_fixed_defaults(self):
        for masked in ([p for p in module.MASKED_DEFAULTS if p != '/sys/devices/virtual/powercap'],
                       ['/proc/acpi', '/proc/kcore', '/sys/firmware', '/proc/new_kernel_protection']):
            with self.subTest(masked=masked):
                previous = self.deployment()
                previous['HostConfig']['MaskedPaths'] = masked
                module.validate_configuration(previous)
                self.assertEqual(module.protected_paths(previous['HostConfig'], 'MaskedPaths'), sorted(masked))

    def test_empty_duplicate_or_noncanonical_protection_is_rejected(self):
        invalid = [None, [], {}, '/proc/kcore', ['relative'], ['/proc'], ['/etc/passwd'],
                   ['/proc/../etc'], ['/proc/./keys'], ['/proc//keys'], ['/proc/keys/'],
                   ['/proc/a\nb'], ['/proc/a\x7fb'], [123], ['/proc/keys', '/proc/keys']]
        for key in ('MaskedPaths', 'ReadonlyPaths'):
            for value in invalid:
                with self.subTest(key=key, value=value):
                    previous = self.deployment()
                    previous['HostConfig'][key] = value
                    with self.assertRaisesRegex(RuntimeError, key):
                        module.validate_configuration(previous)

    def test_protection_order_is_semantic_but_missing_or_extra_paths_are_not(self):
        previous = self.deployment()
        current = copy.deepcopy(previous)
        for key in ('MaskedPaths', 'ReadonlyPaths'):
            current['HostConfig'][key] = list(reversed(previous['HostConfig'][key]))
        module.verify_configuration(previous, current)
        for key in ('MaskedPaths', 'ReadonlyPaths'):
            for change in ('missing', 'extra'):
                with self.subTest(key=key, change=change):
                    current = copy.deepcopy(previous)
                    if change == 'missing':
                        current['HostConfig'][key].pop()
                    else:
                        current['HostConfig'][key].append('/proc/new-protected-path')
                    with self.assertRaisesRegex(RuntimeError, 'HostConfig.' + key):
                        module.verify_configuration(previous, current)

    def test_configuration_diff_reports_all_field_names_without_secret_values(self):
        previous = self.deployment()
        current = copy.deepcopy(previous)
        current['Config'].update(Env=['OPAQUE=replacement-secret'], User='sensitive-user', NewUnknownField='private-value')
        current['HostConfig'].update(LogConfig={'Type': 'other-secret'}, PidsLimit=123)
        current['Mounts'][0]['Source'] = '/private/changed'
        with self.assertRaises(RuntimeError) as caught:
            module.verify_configuration(previous, current)
        message = str(caught.exception)
        for field in ('Config.Env', 'Config.User', 'Config.NewUnknownField', 'HostConfig.LogConfig', 'HostConfig.PidsLimit', 'Mounts'):
            self.assertIn(field, message)
        for opaque in ('replacement-secret', 'test-secret-do-not-print', 'sensitive-user', 'private-value', 'other-secret', '/private/changed'):
            self.assertNotIn(opaque, message)

    def test_validation_reports_multiple_unreviewed_fields_without_values(self):
        previous = self.deployment()
        previous['HostConfig'].update(CapAdd=['secret-capability-value'], Devices=['secret-device-value'], MaskedPaths=[])
        with self.assertRaises(RuntimeError) as caught:
            module.validate_configuration(previous)
        for field in ('CapAdd', 'Devices', 'MaskedPaths'):
            self.assertIn(field, str(caught.exception))
        self.assertNotIn('secret-', str(caught.exception))

    def test_only_the_eleven_reviewed_host_lists_allow_null_empty_list_equivalence(self):
        self.assertEqual(module.OPTIONAL_HOST_LISTS, self.OPTIONAL_HOST_LISTS)
        self.assertEqual(len(self.OPTIONAL_HOST_LISTS), 11)
        for key in self.OPTIONAL_HOST_LISTS:
            for left, right in ((None, []), ([], None), (None, None), ([], [])):
                with self.subTest(key=key, left=left, right=right):
                    previous = self.deployment()
                    current = copy.deepcopy(previous)
                    previous['HostConfig'][key] = left
                    current['HostConfig'][key] = right
                    self.assertTrue(module.same_empty_host_list(key, left, right))
                    module.validate_configuration(previous)
                    module.verify_configuration(previous, current)

    def test_optional_host_list_compatibility_rejects_nonempty_and_wrong_types(self):
        for key in self.OPTIONAL_HOST_LISTS:
            for empty in (None, []):
                for changed in (False, 0, {}, '', (), ['private-setting-value']):
                    with self.subTest(key=key, empty=empty, changed=changed):
                        previous = self.deployment()
                        current = copy.deepcopy(previous)
                        previous['HostConfig'][key] = empty
                        current['HostConfig'][key] = changed
                        self.assertFalse(module.same_empty_host_list(key, empty, changed))
                        self.assertFalse(module.same_empty_host_list(key, changed, empty))
                        with self.assertRaisesRegex(RuntimeError, 'HostConfig.' + key) as caught:
                            module.verify_configuration(previous, current)
                        self.assertNotIn('private-setting-value', str(caught.exception))

    def test_unknown_or_nonoptional_host_fields_do_not_get_empty_list_equivalence(self):
        for key in ('UnknownNewList', 'CapAdd', 'Mounts', 'Binds', 'SecurityOpt'):
            with self.subTest(key=key):
                previous = self.deployment()
                current = copy.deepcopy(previous)
                previous['HostConfig'][key] = None
                current['HostConfig'][key] = []
                self.assertFalse(module.same_empty_host_list(key, None, []))
                with self.assertRaisesRegex(RuntimeError, 'HostConfig.' + key):
                    module.verify_configuration(previous, current)

    def test_host_difference_report_shows_only_safe_value_shapes(self):
        previous = self.deployment()
        previous['HostConfig'].update(Dns=None, Ulimits=[])
        current = copy.deepcopy(previous)
        current['HostConfig'].update(Dns=['private-dns-value'], Ulimits=[{'Name': 'private-limit-value'}])
        with self.assertRaises(RuntimeError) as caught:
            module.verify_configuration(previous, current)
        message = str(caught.exception)
        self.assertIn('HostConfig.Dns [null -> list(1)]', message)
        self.assertIn('HostConfig.Ulimits [list(0) -> list(1)]', message)
        self.assertNotIn('private-', message)

    def test_env_file_keeps_secrets_out_of_process_arguments_and_preserves_limits(self):
        previous = self.deployment()
        args = module.create_args(previous, 'sha256:new', 'candidate-only', '/private/container.env')
        self.assertEqual(args[0], 'create')
        self.assertNotIn('-d', args)
        self.assertNotIn('-e', args)
        self.assertNotIn('test-secret-do-not-print', ' '.join(args))
        self.assertEqual(args[args.index('--env-file') + 1], '/private/container.env')
        self.assertEqual(args[args.index('--name') + 1], 'candidate-only')
        self.assertEqual(args[args.index('--log-driver') + 1], 'json-file')
        self.assertEqual(args[args.index('--pids-limit') + 1], '-1')
        self.assertEqual(args[args.index('--cpu-quota') + 1], '0')
        self.assertIn(b'OPAQUE=test-secret-do-not-print\n', module.environment_bytes(previous))

    def test_env_file_rejects_ambiguous_or_multiline_keys_without_echoing_them(self):
        for values in (['A=one', 'A=two'], ['A=line1\nprivate-value'], ['=private-value'],
                       [' #comment=private-value'], ['A\x00B=private-value'], ['MISSING_EQUALS']):
            with self.subTest(values=values):
                previous = self.deployment()
                previous['Config']['Env'] = values
                with self.assertRaises(RuntimeError) as caught:
                    module.environment_bytes(previous)
                self.assertNotIn('private-value', str(caught.exception))

    def test_candidate_identity_and_created_state_are_required(self):
        previous = self.deployment()
        for field, value in (('Id', 'c' * 64), ('Image', 'sha256:other'),
                             ('State', {'Running': True, 'Status': 'running'}),
                             ('State', {'Running': False, 'Status': 'exited'})):
            with self.subTest(field=field, value=value):
                candidate = self.stopped_candidate(previous)
                candidate[field] = value
                with self.assertRaisesRegex(RuntimeError, 'identity/state'):
                    module.verify_stopped_candidate(previous, candidate, 'sha256:candidate', 'b' * 64)

    def test_prepare_failures_never_stop_start_or_rename_running_predecessor(self):
        for failure in ('configuration', 'timeout', 'receipt-before-create', 'receipt-after-create'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temp:
                directory = pathlib.Path(temp)
                previous = self.deployment()
                candidate = self.stopped_candidate(previous)
                candidate['Config']['Env'] = ['OPAQUE=changed-secret']
                record = {'container': 'control'}
                def write(path, value):
                    if pathlib.Path(path).name == 'receipt.json' and (
                            failure == 'receipt-before-create' or failure == 'receipt-after-create' and value.get('candidateId')):
                        raise OSError('test disk full')
                    self.local_private_write(path, value)
                with patch.object(module, 'private_write', side_effect=write), \
                     patch.object(module, 'docker', return_value=('b' * 64).encode()) as docker, \
                     patch.object(module, 'inspect', return_value=candidate), \
                     patch.object(module, 'preview') as preview:
                    if failure == 'timeout':
                        docker.side_effect = RuntimeError('Docker timed out: create')
                    with self.assertRaises((RuntimeError, OSError)) as caught:
                        module.prepare_candidate(previous, 'sha256:candidate', directory, record, 'source-hash')
                    self.assertNotIn('changed-secret', str(caught.exception))
                    self.assertFalse(any(call.args[0] in ('stop', 'start', 'rename') for call in docker.call_args_list))
                    preview.assert_not_called()

    def test_prepare_success_rechecks_same_stopped_candidate_before_returning_id(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = pathlib.Path(temp)
            previous = self.deployment()
            candidate = self.stopped_candidate(previous)
            record = {'container': 'control'}
            with patch.object(module, 'private_write', side_effect=self.local_private_write), \
                 patch.object(module, 'docker', return_value=('b' * 64).encode()) as docker, \
                 patch.object(module, 'inspect', return_value=candidate) as inspect, \
                 patch.object(module, 'preview', return_value=({'sourceSha256': 'source-hash'}, previous, b'', b'')):
                result = module.prepare_candidate(previous, 'sha256:candidate', directory, record, 'source-hash')
            self.assertEqual(result, 'b' * 64)
            self.assertEqual(record['status'], 'candidate-verified')
            self.assertEqual([call.args for call in inspect.call_args_list], [('b' * 64,), ('b' * 64,)])
            self.assertEqual(len(docker.call_args_list), 1)
            self.assertEqual(docker.call_args.args[0], 'create')
            self.assertEqual(json.loads((directory / 'receipt.json').read_text())['candidateId'], result)

    def test_prepare_rejects_original_config_changed_while_building(self):
        with tempfile.TemporaryDirectory() as temp:
            previous = self.deployment()
            actual = copy.deepcopy(previous)
            actual['HostConfig']['PidsLimit'] = 256
            with patch.object(module, 'private_write', side_effect=self.local_private_write), \
                 patch.object(module, 'docker', return_value=('b' * 64).encode()) as docker, \
                 patch.object(module, 'inspect', return_value=self.stopped_candidate(previous)), \
                 patch.object(module, 'preview', return_value=({'sourceSha256': 'source-hash'}, actual, b'', b'')):
                with self.assertRaisesRegex(RuntimeError, 'HostConfig.PidsLimit'):
                    module.prepare_candidate(previous, 'sha256:candidate', pathlib.Path(temp), {'container': 'control'}, 'source-hash')
                self.assertFalse(any(call.args[0] in ('stop', 'start', 'rename') for call in docker.call_args_list))

    def test_restore_refuses_unrelated_current_container_and_preserves_current_data(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / 'state.json').write_bytes(b'current media events')
            record = {'container': 'control', 'retainedContainer': 'old-control', 'failedContainer': 'failed-control', 'candidateId': 'expected-new'}
            with patch.object(module, 'ROOT', root), \
                 patch.object(module, 'inspect', return_value={'Id': 'unrelated', 'State': {'Running': True}}), \
                 patch.object(module, 'docker') as docker, patch.object(module, 'healthy') as healthy:
                with self.assertRaisesRegex(RuntimeError, 'identity changed'):
                    module.restore({'Id': 'old'}, root, record)
                docker.assert_not_called()
                healthy.assert_not_called()
                self.assertEqual((root / 'state.json').read_bytes(), b'current media events')

    def test_preview_aggregates_configuration_source_and_recording_problems_without_mutation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            host_source = b'host source differs from image'
            (root / 'service.mjs').write_bytes(host_source)
            image_source = (module.OLD_TOKEN + '\n' + module.OLD_EXPIRY).encode()
            active_state = json.dumps({'sequence': 8, 'assets': {}, 'events': [],
                                       'recordings': {'active': {'status': 'recording'}}}).encode()
            with patch.object(module, 'ROOT', root):
                previous = self.deployment()
                previous['HostConfig']['CapAdd'] = ['dummy-sensitive-value']
                def read_only_docker(*args, **kwargs):
                    self.assertEqual(args[:3], ('exec', previous['Id'], 'cat'))
                    return image_source if args[3] == '/app/service.mjs' else active_state
                with patch.object(module, 'current_control', return_value=previous), \
                     patch.object(module, 'docker', side_effect=read_only_docker) as docker, \
                     patch.object(module, 'probe_health'), \
                     patch.object(module, 'private_write') as private_write:
                    with self.assertRaises(RuntimeError) as caught:
                        module.preview()
                    message = str(caught.exception)
                    for issue in ('CapAdd', 'source differ', 'Active platform recordings'):
                        self.assertIn(issue, message)
                    self.assertNotIn('dummy-sensitive-value', message)
                    self.assertNotIn('test-secret-do-not-print', message)
                    self.assertTrue(any(call.args[-1] == '/data/state.json' for call in docker.call_args_list))
                    self.assertTrue(all(call.args[0] == 'exec' for call in docker.call_args_list))
                    private_write.assert_not_called()
                    self.assertEqual((root / 'service.mjs').read_bytes(), host_source)

    def health_deployment(self, host=None, port=None):
        previous = self.deployment()
        if host is not None:
            previous['Config']['Env'].append('MEDIA_LISTEN_HOST=' + host)
        if port is not None:
            previous['Config']['Env'].append('MEDIA_PORT=' + port)
        return previous

    def test_health_url_preserves_reviewed_bind_address_and_valid_port(self):
        cases = [(None, None, 'http://127.0.0.1:18190/healthz'),
                 ('10.255.1.1', '18190', 'http://10.255.1.1:18190/healthz'),
                 ('127.0.0.1', '1', 'http://127.0.0.1:1/healthz'),
                 ('0.0.0.0', '65535', 'http://127.0.0.1:65535/healthz'),
                 ('10.255.1.1', '00001', 'http://10.255.1.1:1/healthz')]
        for host, port, expected in cases:
            with self.subTest(host=host, port=port):
                self.assertEqual(module.health_url(self.health_deployment(host, port)), expected)

    def test_health_url_rejects_unreviewed_hosts_and_invalid_ports(self):
        for host in ('', 'localhost', '10.255.1.2', 'https://10.255.1.1', '127.0.0.1@private.example',
                     '::1', '[::1]', '10.255.1.1\n', '10.255.1.1/path'):
            with self.subTest(host=host):
                with self.assertRaisesRegex(RuntimeError, 'listen address'):
                    module.health_url(self.health_deployment(host, '18190'))
        for port in ('', '0', '65536', '-1', '+80', ' 80', '80\n', '80.0', '0x50',
                     '\u00b2', '\u0661\u0668\u0661\u0669\u0660', '9' * 1000):
            with self.subTest(port=port):
                with self.assertRaisesRegex(RuntimeError, 'listen port'):
                    module.health_url(self.health_deployment('10.255.1.1', port))

    @staticmethod
    def health_response(payload=b'{"status":"running"}', status=200):
        response = MagicMock()
        response.__enter__.return_value = response
        response.getcode.return_value = status
        response.read.return_value = payload
        return response

    def test_probe_health_uses_configured_endpoint_without_proxy_and_reads_bounded_json(self):
        previous = self.health_deployment('10.255.1.1', '18190')
        response = self.health_response()
        opener = MagicMock()
        opener.open.return_value = response
        with patch.object(module.urllib.request, 'build_opener', return_value=opener) as build:
            module.probe_health(previous)
        handlers = build.call_args.args
        self.assertEqual(len(handlers), 2)
        self.assertIsInstance(handlers[0], module.urllib.request.ProxyHandler)
        self.assertEqual(handlers[0].proxies, {})
        self.assertIsInstance(handlers[1], module.NoHealthRedirect)
        opener.open.assert_called_once_with('http://10.255.1.1:18190/healthz', timeout=3)
        response.read.assert_called_once_with(4097)

    def test_health_redirect_handler_does_not_follow_an_external_location(self):
        request = module.urllib.request.Request('http://10.255.1.1:18190/healthz')
        handler = module.NoHealthRedirect()
        headers = Message()
        headers['Location'] = 'https://untrusted.invalid/private'
        requests = []
        class InMemoryTransport(module.urllib.request.BaseHandler):
            def default_open(self, req):
                # Intercept every scheme before a network handler can run.
                requests.append(req.full_url)
                status = 302 if len(requests) == 1 else 200
                response = urllib.response.addinfourl(io.BytesIO(b'{}'), headers, req.full_url, status)
                response.msg = 'Found' if status == 302 else 'OK'
                return response
        opener = module.urllib.request.build_opener(module.urllib.request.ProxyHandler({}), handler, InMemoryTransport())
        with self.assertRaises(urllib.error.HTTPError):
            opener.open(request)
        self.assertEqual(requests, ['http://10.255.1.1:18190/healthz'])
        self.assertIsNone(handler.redirect_request(request, None, 302, 'Found', {}, 'https://untrusted.invalid'))

    def test_probe_health_rejects_bad_status_oversized_or_invalid_json_without_echoing_body(self):
        cases = [(200, b'x' * 4097), (200, b'\xffprivate-payload'), (200, b'private-payload'),
                 (200, b'[]'), (200, b'"private-payload"'), (200, b'{"status":"private-payload"}'),
                 (302, b'private-payload'), (503, b'private-payload')]
        for status, payload in cases:
            with self.subTest(status=status, payload_size=len(payload)):
                response = self.health_response(payload, status)
                opener = MagicMock()
                opener.open.return_value = response
                with patch.object(module.urllib.request, 'build_opener', return_value=opener):
                    with self.assertRaises(RuntimeError) as caught:
                        module.probe_health(self.health_deployment('10.255.1.1', '18190'))
                self.assertNotIn('private-payload', str(caught.exception))
                self.assertIn('http://10.255.1.1:18190/healthz', str(caught.exception))
                if status == 200:
                    response.read.assert_called_once_with(4097)
                else:
                    response.read.assert_not_called()

    def test_probe_health_transport_errors_do_not_echo_exception_payloads(self):
        for error in (TimeoutError('private-transport-info'), urllib.error.URLError('private-transport-info')):
            with self.subTest(error=type(error).__name__):
                opener = MagicMock()
                opener.open.side_effect = error
                with patch.object(module.urllib.request, 'build_opener', return_value=opener):
                    with self.assertRaises(RuntimeError) as caught:
                        module.probe_health(self.health_deployment('10.255.1.1', '18190'))
                self.assertNotIn('private-transport-info', str(caught.exception))
                self.assertIn(type(error).__name__, str(caught.exception))

    def test_healthy_retries_same_endpoint_with_a_bounded_deadline(self):
        previous = self.health_deployment('10.255.1.1', '18190')
        with patch.object(module.time, 'monotonic', side_effect=[0, 0, 1]), \
             patch.object(module.time, 'sleep') as sleep, \
             patch.object(module, 'probe_health', side_effect=[RuntimeError('safe health failure'), None]) as probe:
            module.healthy(previous)
            self.assertEqual([call.args for call in probe.call_args_list], [(previous,), (previous,)])
            sleep.assert_called_once_with(1)
        with patch.object(module.time, 'monotonic', side_effect=[0, 0, 46]), \
             patch.object(module.time, 'sleep'), \
             patch.object(module, 'probe_health', side_effect=RuntimeError('safe health failure')) as probe:
            with self.assertRaisesRegex(RuntimeError, 'startup health deadline exceeded'):
                module.healthy(previous)
            probe.assert_called_once_with(previous)

    def test_apply_health_failure_in_initial_preview_never_creates_or_stops_container(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            source = (module.OLD_TOKEN + '\n' + module.OLD_EXPIRY).encode()
            (root / 'service.mjs').write_bytes(source)
            state = b'{"sequence":1,"assets":{},"events":[],"recordings":{}}'
            with patch.object(module, 'ROOT', root):
                previous = self.health_deployment('10.255.1.1', '18190')
                def read_only(*args, **kwargs):
                    self.assertEqual(args[:3], ('exec', previous['Id'], 'cat'))
                    return source if args[3] == '/app/service.mjs' else state
                with patch.object(module, 'current_control', return_value=previous), \
                     patch.object(module, 'docker', side_effect=read_only) as docker, \
                     patch.object(module, 'probe_health', side_effect=RuntimeError('Control health check failed at configured endpoint')), \
                     patch.object(module, 'private_write') as write:
                    with self.assertRaisesRegex(RuntimeError, 'Preflight checks failed'):
                        module.apply(previous['Image'], module.sha(source))
                    self.assertTrue(all(call.args[0] == 'exec' for call in docker.call_args_list))
                    write.assert_not_called()
                    self.assertFalse((root / '.local').exists())

    def test_failure_summary_records_stage_and_type_without_opaque_error_text(self):
        cases = (OSError(errno.EACCES, 'private-env-value', '/private/file'),
                 ValueError('private-response-body'),
                 subprocess.TimeoutExpired(['docker', '-e', 'KEY=private-env-value'], 3))
        for error in cases:
            with self.subTest(error=type(error).__name__):
                result = module.failure_summary(error, 'check-candidate-health')
                self.assertEqual(result['stage'], 'check-candidate-health')
                self.assertEqual(result['type'], type(error).__name__)
                self.assertNotIn('private-', json.dumps(result))
        self.assertEqual(module.failure_summary(RuntimeError('Docker failed: start'), 'start-candidate'),
                         {'stage': 'start-candidate', 'type': 'RuntimeError', 'reason': 'Docker failed: start'})

    def test_candidate_health_failure_restores_with_same_configured_endpoint_and_current_data(self):
        self.apply_scenario(candidate_health_failure=True)

    def test_candidate_and_recovery_health_failures_record_both_safe_stages(self):
        self.apply_scenario(candidate_health_failure=True, recovery_health_failure=True)

    def test_apply_creates_verifies_then_starts_exact_candidate_and_keeps_current_data(self):
        self.apply_scenario()

    def test_apply_accepts_all_eleven_null_lists_recreated_as_empty_lists(self):
        self.apply_scenario(optional_null_lists=True)

    def test_apply_rejects_real_dns_device_or_ulimit_additions_before_stopping_old_service(self):
        changes = ({'Dns': ['203.0.113.5']},
                   {'Devices': [{'PathOnHost': '/dev/test-only', 'PathInContainer': '/dev/test-only', 'CgroupPermissions': 'r'}]},
                   {'Ulimits': [{'Name': 'nofile', 'Soft': 1024, 'Hard': 2048}]})
        for changed in changes:
            with self.subTest(changed=changed):
                self.apply_scenario(optional_null_lists=True, candidate_host_changes=changed)

    def test_apply_never_records_success_if_started_container_identity_or_state_changed(self):
        for changed in ({'Id': 'd' * 64}, {'Image': 'sha256:unexpected'},
                        {'State': {'Running': False, 'Status': 'exited'}},
                        {'State': {'Running': True, 'Status': 'created'}}):
            with self.subTest(changed=changed):
                self.apply_scenario(changed)

    def apply_scenario(self, changed_after_start=None, optional_null_lists=False, candidate_host_changes=None,
                       candidate_health_failure=False, recovery_health_failure=False):
        with tempfile.TemporaryDirectory() as temp, ExitStack() as stack:
            root = pathlib.Path(temp)
            data = root / '.local/data'
            data.mkdir(parents=True)
            original_state = {'sequence': 2, 'assets': {'old-asset': {}}, 'events': [], 'recordings': {}}
            (data / 'state.json').write_text(json.dumps(original_state))
            (data / 'old-video.mp4').write_bytes(b'existing-media-must-survive')
            source = (module.OLD_TOKEN + '\n' + module.OLD_EXPIRY).encode()
            changed = module.updated_source(source)
            (root / 'service.mjs').write_bytes(source)
            stack.enter_context(patch.object(module, 'ROOT', root))
            previous = self.deployment()
            previous['Config']['Env'] += ['MEDIA_LISTEN_HOST=10.255.1.1', 'MEDIA_PORT=18190']
            if optional_null_lists:
                previous['HostConfig'].update({key: None for key in self.OPTIONAL_HOST_LISTS})
            candidate_id, image = 'b' * 64, 'sha256:' + 'c' * 64
            old = copy.deepcopy(previous)
            candidate = self.stopped_candidate(previous, image, candidate_id)
            if optional_null_lists:
                candidate['HostConfig'].update({key: [] for key in self.OPTIONAL_HOST_LISTS})
            if candidate_host_changes:
                candidate['HostConfig'].update(candidate_host_changes)
            current_name = previous['Name'].lstrip('/')
            aliases = {current_name: previous['Id']}
            containers = {previous['Id']: old}
            events = []
            health_calls = []
            plan = {'container': current_name, 'containerId': previous['Id'], 'imageId': previous['Image'], 'sourceSha256': module.sha(source)}
            def preview():
                events.append(('preview',))
                return copy.deepcopy(plan), copy.deepcopy(previous), source, changed
            def inspect(reference):
                events.append(('inspect', reference))
                if reference == image:
                    return {'Id': image, 'Config': copy.deepcopy(previous['Config'])}
                if reference.startswith('helmet-media-control:ttl30-'):
                    return {'Id': image}
                value = copy.deepcopy(containers[aliases.get(reference, reference)])
                if changed_after_start and reference == current_name and candidate['State']['Running']:
                    value.update(changed_after_start)
                return value
            def docker(*args, **kwargs):
                events.append(tuple(args))
                operation = args[0]
                if operation == 'create':
                    self.assertNotIn('test-secret-do-not-print', ' '.join(args))
                    self.assertTrue(old['State']['Running'])
                    containers[candidate_id] = candidate
                    aliases[args[args.index('--name') + 1]] = candidate_id
                    return candidate_id.encode()
                if operation == 'stop':
                    self.assertIn(args[-1], containers)
                    containers[args[-1]]['State'] = {'Running': False, 'Status': 'exited'}
                elif operation == 'rename':
                    identity, name = args[1:]
                    self.assertIn(identity, containers)
                    for alias in list(aliases):
                        if aliases[alias] == identity:
                            del aliases[alias]
                    aliases[name] = identity
                    containers[identity]['Name'] = '/' + name
                elif operation == 'start':
                    self.assertIn(args[1], containers)
                    if args[1] == candidate_id:
                        self.assertFalse(old['State']['Running'])
                    else:
                        self.assertTrue(candidate_health_failure)
                        self.assertFalse(candidate['State']['Running'])
                    containers[args[1]]['State'] = {'Running': True, 'Status': 'running'}
                elif operation == 'exec':
                    self.assertEqual(args[1], candidate_id)
                    return changed
                return b''
            def private_write(path, value):
                if pathlib.Path(path).name == 'receipt.json':
                    events.append(('receipt', value.get('status')))
                self.local_private_write(path, value)
            def healthy(configured):
                self.assertEqual(configured, previous)
                health_calls.append(module.health_url(configured))
                events.append(('healthy',))
                after = copy.deepcopy(original_state)
                after['sequence'] = 3
                after['events'].append({'sequence': 3, 'type': 'new-event'})
                (data / 'state.json').write_text(json.dumps(after))
                if candidate_health_failure and len(health_calls) == 1:
                    raise OSError(errno.ECONNREFUSED, 'private-candidate-error', '/private/opaque-path')
                if recovery_health_failure and len(health_calls) == 2:
                    raise OSError(errno.EIO, 'private-recovery-error', '/private/opaque-path')
            stack.enter_context(patch.object(module, 'preview', side_effect=preview))
            stack.enter_context(patch.object(module, 'inspect', side_effect=inspect))
            stack.enter_context(patch.object(module, 'docker', side_effect=docker))
            stack.enter_context(patch.object(module, 'private_write', side_effect=private_write))
            stack.enter_context(patch.object(module, 'healthy', side_effect=healthy))
            if candidate_health_failure:
                with self.assertRaises(RuntimeError) as caught:
                    module.apply(previous['Image'], module.sha(source))
                receipt_file = next((root / '.local').glob('playback-ttl-patch-*/receipt.json'))
                receipt = json.loads(receipt_file.read_text())
                self.assertEqual(health_calls, ['http://10.255.1.1:18190/healthz'] * 2)
                self.assertEqual(receipt['failure'], {'stage': 'check-candidate-health', 'type': 'ConnectionRefusedError', 'errno': errno.ECONNREFUSED})
                if recovery_health_failure:
                    self.assertEqual(receipt['status'], 'compatible-recovery-incomplete')
                    self.assertEqual(receipt['recoveryFailure'], {'stage': 'check-predecessor-health', 'type': 'OSError', 'errno': errno.EIO})
                    self.assertIn('check-candidate-health', str(caught.exception))
                    self.assertIn('check-predecessor-health', str(caught.exception))
                else:
                    self.assertEqual(receipt['status'], 'compatible-predecessor-restored')
                    self.assertEqual(receipt['recoveryStage'], 'predecessor-healthy')
                self.assertNotIn('private-', str(caught.exception))
                self.assertNotIn('private-', json.dumps(receipt.get('failure')) + json.dumps(receipt.get('recoveryFailure')))
                self.assertNotIn(('receipt', 'deployed'), events)
                self.assertTrue(old['State']['Running'])
                self.assertFalse(candidate['State']['Running'])
                self.assertEqual(json.loads((data / 'state.json').read_text())['sequence'], 3)
                self.assertEqual((data / 'old-video.mp4').read_bytes(), b'existing-media-must-survive')
                return
            if candidate_host_changes:
                restore = stack.enter_context(patch.object(module, 'restore'))
                with self.assertRaisesRegex(RuntimeError, 'Stopped candidate preflight failed'):
                    module.apply(previous['Image'], module.sha(source))
                restore.assert_not_called()
                self.assertTrue(old['State']['Running'])
                self.assertFalse(any(item[0] in ('stop', 'start', 'rename') for item in events))
                self.assertNotIn(('receipt', 'deployed'), events)
                self.assertEqual((root / 'service.mjs').read_bytes(), source)
                self.assertEqual(json.loads((data / 'state.json').read_text()), original_state)
                self.assertEqual((data / 'old-video.mp4').read_bytes(), b'existing-media-must-survive')
                return
            if changed_after_start:
                # Recovery itself has separate tests with exact container IDs.
                restore = stack.enter_context(patch.object(module, 'restore'))
                with self.assertRaises(RuntimeError):
                    module.apply(previous['Image'], module.sha(source))
                restore.assert_called_once()
                self.assertNotIn(('receipt', 'deployed'), events)
                self.assertNotIn(('tag', image, previous['Config']['Image']), events)
                self.assertEqual((root / 'service.mjs').read_bytes(), source)
                self.assertEqual((data / 'old-video.mp4').read_bytes(), b'existing-media-must-survive')
                return
            result = module.apply(previous['Image'], module.sha(source))
            stop_at = next(i for i, item in enumerate(events) if item[0] == 'stop')
            verified_at = events.index(('receipt', 'candidate-verified'))
            self.assertLess(verified_at, stop_at)
            self.assertGreaterEqual(events[:stop_at].count(('inspect', candidate_id)), 3)
            self.assertEqual(sum(item[0] == 'create' for item in events), 1)
            self.assertEqual([item for item in events if item[0] == 'start'], [('start', candidate_id)])
            self.assertFalse(any(item[0] == 'run' and '-d' in item for item in events))
            self.assertEqual(result['status'], 'deployed')
            self.assertEqual(result['currentContainerId'], candidate_id)
            self.assertFalse(result['dataRestored'])
            self.assertEqual((root / 'service.mjs').read_bytes(), changed)
            self.assertEqual(json.loads((data / 'state.json').read_text())['sequence'], 3)
            self.assertEqual((data / 'old-video.mp4').read_bytes(), b'existing-media-must-survive')


if __name__ == '__main__':
    unittest.main()
