import base64
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('snapshot', Path(__file__).with_name('snapshot_export.py'))
snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshot)


class SnapshotExportTest(unittest.TestCase):
    def test_counts_come_from_single_row_dump_and_empty_tables_remain(self):
        data = b'''CREATE TABLE `wearable_device` (id int);
CREATE TABLE `wearable_business_meta` (id int);
CREATE TABLE `wearable_device_report` (id int);
INSERT INTO `wearable_device` (`id`) VALUES (1);
INSERT INTO `wearable_device` (`id`) VALUES (2);
INSERT INTO `wearable_business_meta` (`id`) VALUES (1);
'''
        self.assertEqual({'wearable_device': 2, 'wearable_business_meta': 1, 'wearable_device_report': 0}, snapshot.dump_counts(data))
        with self.assertRaises(ValueError):
            snapshot.dump_counts(data + b'INSERT INTO `unlisted` (`id`) VALUES (1);\n')

    def test_existing_key_required_and_never_generated(self):
        key = base64.b64encode(bytes(range(32))).decode()
        self.assertEqual(key, snapshot.media_key({'Config': {'Env': [snapshot.KEY_NAME + '=' + key]}}))
        for values in ([], [snapshot.KEY_NAME + '=invalid'], [snapshot.KEY_NAME + '=' + key] * 2):
            with self.subTest(values=len(values)), self.assertRaises(ValueError):
                snapshot.media_key({'Config': {'Env': values}})

    def test_source_identity_and_volume_are_checked_before_export(self):
        import json
        good = {'Name': '/melhat-mysql', 'State': {'Running': True},
                'Mounts': [{'Destination': '/var/lib/mysql', 'Type': 'volume', 'Name': 'local-dev_melhat-mysql-data'}],
                'Config': {'Labels': {'com.docker.compose.project': 'local-dev'}}}
        with patch.object(snapshot, 'run', return_value=json.dumps([good]).encode()):
            self.assertEqual(good, snapshot.inspect_source('melhat-mysql', 'local-dev_melhat-mysql-data', '/var/lib/mysql'))
            with self.assertRaises(ValueError):
                snapshot.inspect_source('another-mysql', 'local-dev_melhat-mysql-data', '/var/lib/mysql')
            with self.assertRaises(ValueError):
                snapshot.inspect_source('melhat-mysql', 'another-volume', '/var/lib/mysql')

    def test_output_is_new_and_scoped(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(snapshot, 'PRIVATE_ROOT', Path(folder) / 'snapshots'):
            destination = Path(folder) / 'snapshots' / 'source-20261027T120000Z-01234567'
            self.assertEqual(destination, snapshot.prepare_destination(destination))
            self.assertTrue((destination / 'INCOMPLETE').exists())
            with self.assertRaises(ValueError):
                snapshot.prepare_destination(destination)
            with self.assertRaises(ValueError):
                snapshot.prepare_destination(Path(folder) / destination.name)

    def test_schema_hash_ignores_live_sequence_but_detects_ddl(self):
        with patch.object(snapshot, 'run', side_effect=[b'id int AUTO_INCREMENT=12', b'id int AUTO_INCREMENT=15', b'id bigint AUTO_INCREMENT=15']):
            first = snapshot.schema_signature({'table': 'InnoDB'})
            self.assertEqual(first, snapshot.schema_signature({'table': 'InnoDB'}))
            self.assertNotEqual(first, snapshot.schema_signature({'table': 'InnoDB'}))


if __name__ == '__main__':
    unittest.main()
