import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('guard', Path(__file__).with_name('original_service_guard.py'))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


def container(identifier='a' * 64, project='existing-project'):
    return {'Id': identifier, 'Name': '/private-name', 'RestartCount': 0,
            'Config': {'Labels': {'com.docker.compose.project': project},
                       'Env': ['SECRET=never-persist-this'], 'Cmd': ['private-command'],
                       'ExposedPorts': {'80/tcp': {}}},
            'HostConfig': {'NetworkMode': 'bridge', 'PortBindings': {'80/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '9000'}]}},
            'NetworkSettings': {'Ports': {'80/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '9000'}]}},
            'Mounts': [{'Source': '/private/path', 'Destination': '/data', 'Type': 'bind', 'RW': True}],
            'State': {'StartedAt': '2026-10-27T00:00:00Z', 'Running': True, 'Status': 'running',
                      'Health': {'Status': 'healthy'}}}


def observation(*rows):
    return {'formatVersion': 1, 'kind': 'original-container-snapshot', 'excludedProject': guard.STAGING_PROJECT,
            'excludedStagingCount': 0, 'containers': {row['Id']: guard.safe_container(row) for row in rows}}


class OriginalServiceGuardTest(unittest.TestCase):
    def test_saved_projection_never_contains_credentials_names_addresses_or_paths(self):
        value = json.dumps(guard.safe_container(container()))
        for secret in ('never-persist-this', 'private-command', 'private-name', '/private/path', '127.0.0.1', '9000'):
            self.assertNotIn(secret, value)
        self.assertIn('portConfigSha256', value)
        self.assertIn('mountConfigSha256', value)

    def test_only_exact_staging_project_is_excluded(self):
        original, staging = container(), container('b' * 64, guard.STAGING_PROJECT)
        similar = container('c' * 64, guard.STAGING_PROJECT + '-other')
        with patch.object(guard, 'docker_read', side_effect=[b'aaaaaaaaaaaa bbbbbbbbbbbb cccccccccccc',
                          json.dumps([original, staging, similar]).encode()]):
            result = guard.observe()
        self.assertEqual({'a' * 64, 'c' * 64}, set(result['containers']))
        self.assertEqual(1, result['excludedStagingCount'])

    def test_same_originals_pass_despite_staging_count(self):
        before = observation(container())
        after = copy.deepcopy(before)
        after['excludedStagingCount'] = 4
        self.assertTrue(guard.compare(before, after)['summary']['unchanged'])

    def test_restart_ports_mounts_and_health_changes_are_detected(self):
        before = observation(container())
        row = container()
        row['RestartCount'] = 1
        row['State']['StartedAt'] = '2026-10-27T01:00:00Z'
        row['State']['Health']['Status'] = 'unhealthy'
        row['HostConfig']['PortBindings']['80/tcp'][0]['HostPort'] = '9001'
        row['Mounts'][0]['Source'] = '/different'
        result = guard.compare(before, observation(row))
        self.assertFalse(result['summary']['unchanged'])
        self.assertEqual({'restartCount', 'startedAt', 'health', 'portConfigSha256', 'mountConfigSha256'},
                         set(result['changedFields']['a' * 64]))

    def test_replacement_is_not_silently_treated_as_same_service(self):
        result = guard.compare(observation(container()), observation(container('b' * 64)))
        self.assertEqual(1, result['summary']['removedCount'])
        self.assertEqual(1, result['summary']['addedCount'])
        self.assertFalse(result['summary']['unchanged'])

    def test_private_evidence_never_overwrites_baseline(self):
        with tempfile.TemporaryDirectory(prefix='.test-original-', dir=str(Path(__file__).resolve().parent)) as folder:
            path = Path(folder) / 'evidence.json'
            guard.private_write_new(path, observation(container()))
            with self.assertRaises(FileExistsError):
                guard.private_write_new(path, {'wrong': 'overwrite'})
            self.assertEqual(1, len(guard.private_read(path)['containers']))

    def test_docker_helper_rejects_all_mutating_commands(self):
        for command in (['stop', 'a' * 64], ['rm', 'a' * 64], ['compose', 'up'], ['inspect', '--all']):
            with self.subTest(command=command), patch.object(guard.subprocess, 'run') as run:
                with self.assertRaises(ValueError):
                    guard.docker_read(command)
                run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
