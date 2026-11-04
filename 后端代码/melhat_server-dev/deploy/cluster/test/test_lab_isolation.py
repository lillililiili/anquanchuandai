import hashlib
import json
import unittest
from unittest.mock import patch
import test_ops as fixture

ops = fixture.ops

class LaboratoryIsolationTest(unittest.TestCase):
    def setUp(self):
        fixture.ConfigurationTest.setUp(self)
        self.labCheckPatch.stop()
        self.private = self.root / 'private' / 'lab'
        self.config = dict(name='wearable-lab-test', networks=dict(cluster=dict(name='wearable-lab-test')),
                           services={'app-a': dict(environment=dict(MELHAT_DB_PRODUCT='dm8', MELHAT_DB_URL='jdbc:dm://wearable-lab-db:5236',
                               MELHAT_DB_USERNAME='WEARABLE_APP', CLUSTER_REDIS_HOST='wearable-lab-redis', CLUSTER_REDIS_DATABASE='0',
                               MELHAT_FILES_STORE_ID='lab-store'), volumes=[dict(target='/shared', source=str(self.root / 'lab-shared'))])})
        self.manifest = dict(project='wearable-lab-test', network=dict(name='wearable-lab-test', id='c'*64),
                             database=dict(containerId='a'*64, schema='WEARABLE_APP'), redis=dict(containerId='b'*64, database=0),
                             sharedDirectory=str(self.root / 'lab-shared'), storeId='lab-store',
                             entrySha256=hashlib.sha256((self.private / 'Caddy.lab').read_bytes()).hexdigest(),
                             backendEnvSha256=hashlib.sha256((self.private / 'backend.env').read_bytes()).hexdigest())
        self.normal = dict(name='normal', networks=dict(cluster=dict(name='normal-network')), services={'app-a': dict(
            environment=dict(MELHAT_DB_URL='jdbc:dm://normal-db:5236', CLUSTER_REDIS_HOST='normal-redis', MELHAT_FILES_STORE_ID='normal-store'),
            volumes=[dict(target='/shared', source=str(self.root / 'normal-shared'))])})
        self.metadata = {
            'a'*64: dict(id='a'*64, name='/wearable-lab-db', networks={'wearable-lab-test': dict(NetworkID='c'*64, Aliases=['wearable-lab-db']),
                       'another-network': dict(NetworkID='d'*64, Aliases=['alternate-db-alias'])}),
            'b'*64: dict(id='b'*64, name='/wearable-lab-redis', networks={'wearable-lab-test': dict(NetworkID='c'*64, Aliases=['wearable-lab-redis'])})}

    def check(self):
        (self.private / 'isolation.json').write_text(json.dumps(self.manifest))
        def call(args, **kwargs):
            if args[1] == 'network':
                return 'c'*64
            if args[1] == 'inspect':
                return json.dumps(self.metadata[args[-1]])
            return json.dumps(self.normal)
        with patch.object(ops, 'call', side_effect=call):
            ops.validate_lab_dependencies(self.config, self.private)

    def test_dedicated_dependencies_and_storage_pass(self):
        self.check()

    def test_normal_project_or_network_cannot_receive_lab_override(self):
        self.config['name'] = 'wearable-cluster'
        with self.assertRaisesRegex(ValueError, 'independent'):
            self.check()

    def test_wrong_container_network_or_backend_config_is_rejected(self):
        self.metadata['a'*64]['networks']['wearable-lab-test']['NetworkID'] = 'd'*64
        with self.assertRaisesRegex(ValueError, 'outside'):
            self.check()
        self.metadata['a'*64]['networks']['wearable-lab-test']['NetworkID'] = 'c'*64
        (self.private / 'backend.env').write_text('changed=true\n')
        with self.assertRaisesRegex(ValueError, 'configuration differs'):
            self.check()

    def test_normal_dependency_overlap_is_detected_through_another_alias(self):
        self.normal['services']['app-a']['environment']['MELHAT_DB_URL'] = 'jdbc:dm://alternate-db-alias:5236'
        with self.assertRaisesRegex(ValueError, 'another alias'):
            self.check()

    def test_shared_storage_or_store_id_overlap_is_rejected(self):
        self.normal['services']['app-a']['environment']['MELHAT_FILES_STORE_ID'] = 'lab-store'
        with self.assertRaisesRegex(ValueError, 'reuse'):
            self.check()

    def test_modified_laboratory_entry_is_rejected(self):
        (self.private / 'Caddy.lab').write_text('# different entry\n')
        with self.assertRaisesRegex(ValueError, 'entry differs'):
            self.check()

if __name__ == '__main__':
    unittest.main()
