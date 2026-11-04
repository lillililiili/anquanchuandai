import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import migrate


class OfflineInventoryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='migration-offline-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = dict(product='mysql', schema='transfer_source', username='migration', password='synthetic-password',
                           url='jdbc:mysql://127.0.0.1:15306/transfer_source', databaseContainerId='a' * 64,
                           backendEnvFile=str(self.root / 'backend.env'))
        self.env = dict(MELHAT_DB_PRODUCT='mysql', MELHAT_DB_URL='jdbc:mysql://source-db:3306/transfer_source',
                        MELHAT_DB_USERNAME='migration', MELHAT_DB_PASSWORD='synthetic-password',
                        MELHAT_CLUSTER_NODE_ID='app-a', JWT_SECRET='synthetic-jwt', MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY='synthetic-media')
        (self.root / 'backend.env').write_text(''.join(f'{k}={v}\n' for k, v in self.env.items()), encoding='utf-8')
        self.database = dict(Id='a' * 64, Name='/source-db', State=dict(Running=True), NetworkSettings=dict(
            Ports={'3306/tcp': [dict(HostPort='15306', HostIp='127.0.0.1')]},
            Networks={'isolated': dict(NetworkID='n' * 64, IPAddress='172.28.0.2', Aliases=['source-db'])}))
        self.app = dict(Id='b' * 64, State=dict(Running=False), Config=dict(Env=[f'{k}={v}' for k, v in self.env.items()]),
                        NetworkSettings=dict(Networks={'isolated': dict(NetworkID='n' * 64)}))

    def capture(self):
        with patch.object(migrate, 'docker_identity', side_effect=lambda value: self.database if value == 'a' * 64 else self.app):
            migrate.stopped_evidence(self.config, ['app-a'], self.root / 'offline.json')

    def test_real_endpoint_mapping_and_stopped_node_are_recorded_without_secrets(self):
        self.capture()
        data = (self.root / 'offline.json').read_text()
        self.assertNotIn('synthetic', data)
        self.assertEqual(json.loads(data)['databaseContainerId'], 'a' * 64)

    def test_same_account_and_node_from_another_database_do_not_prove_offline(self):
        self.app['Config']['Env'] = [value.replace('source-db:3306', 'another-db:3306') for value in self.app['Config']['Env']]
        with self.assertRaises(ValueError):
            self.capture()
        self.assertFalse((self.root / 'offline.json').exists())

    def test_same_alias_on_another_network_does_not_prove_offline(self):
        self.app['NetworkSettings']['Networks']['isolated']['NetworkID'] = 'other-network'
        with self.assertRaises(ValueError):
            self.capture()

    def test_active_node_or_changed_keys_are_rejected(self):
        self.app['State']['Running'] = True
        with self.assertRaises(ValueError):
            self.capture()

    def test_never_started_target_with_explicit_matching_network_can_be_imported(self):
        self.app['State']['Status'] = 'created'
        self.app['HostConfig'] = dict(NetworkMode='isolated')
        self.app['NetworkSettings']['Networks']['isolated']['NetworkID'] = ''
        self.capture()
        self.app['State']['Running'] = False
        self.app['Config']['Env'] = [value.replace('synthetic-media', 'different-key') for value in self.app['Config']['Env']]
        with self.assertRaises(ValueError):
            self.capture()


if __name__ == '__main__':
    unittest.main()
