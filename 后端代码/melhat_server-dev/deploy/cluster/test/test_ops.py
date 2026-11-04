"""Render real Compose without starting services; reject unsafe operator inputs."""
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

DEPLOY = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('cluster_ops', DEPLOY / 'ops.py')
ops = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ops)

class ConfigurationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='wearable-compose-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'private').mkdir()
        (self.root / 'shared' / 'files').mkdir(parents=True)
        for name in ('compose.yml', 'compose.lab.yml', 'application-cluster.yml', 'logback-cluster.xml', 'Caddyfile', 'Caddy.backend'):
            shutil.copyfile(DEPLOY / name, self.root / name)
        shutil.copyfile(DEPLOY / 'Caddyfile', self.root / 'private' / 'Caddy.lab')
        secret = base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip('=')
        values = dict(MELHAT_DB_PRODUCT='dm8', MELHAT_DB_URL='jdbc:dm://test-db:5236', MELHAT_DB_USERNAME='TEST',
                      MELHAT_DB_PASSWORD=secret, CLUSTER_REDIS_HOST='test-redis', CLUSTER_REDIS_PASSWORD=secret,
                      JWT_SECRET=secret, MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY=secret,
                      MELHAT_FILES_STORE_ID='42bb991a-a149-4a82-94f3-62aca3b41fb1', MELHAT_CLUSTER_ADMIN_TOKEN=secret)
        (self.root / 'private' / 'backend.env').write_text(''.join(f'{key}={value}\n' for key, value in values.items()))
        for kind in ('helmet', 'belt'):
            for node in ('a', 'b'):
                (self.root / 'private' / f'{kind}-{node}.json').write_text(json.dumps(dict(adminToken=secret, upstreamOrigin=f'http://app-{node}:18084')))
        (self.root / 'private' / 'Caddy.devices').write_text('# test routes\n')
        files = {name: hashlib.sha256((self.root / 'private' / name).read_bytes()).hexdigest()
                 for name in ('helmet-a.json', 'helmet-b.json', 'belt-a.json', 'belt-b.json', 'Caddy.devices')}
        (self.root / 'private' / 'gateway-manifest.json').write_text(json.dumps(dict(generation='42bb991a-a149-4a82-94f3-62aca3b41fb1', files=files)))
        self.dotenv = f'BACKEND_IMAGE=wearable-backend:lab\nGATEWAY_IMAGE=wearable-gateway:lab\nMELHAT_DB_PRODUCT=dm8\nSHARED_DATA_DIR={self.root.as_posix()}/shared\nCADDY_SITE=http://:80\n'
        self.dotenv += 'PC_STATIC_UPSTREAM=pc-static:80\nMEDIA_UPSTREAM=media:18190\nSIP_UPSTREAM=freeswitch:5066\n'
        (self.root / '.env').write_text(self.dotenv)
        lab = self.root / 'private' / 'lab'
        lab.mkdir()
        for item in (self.root / 'private').iterdir():
            if item.is_file():
                shutil.copyfile(item, lab / item.name)
        (self.root / '.lab.env').write_text(self.dotenv + 'CLUSTER_PROJECT=wearable-lab-test\nCLUSTER_NETWORK=wearable-lab-test\n')
        ops.ROOT = self.root
        ops.COMPOSE = ['docker', 'compose', '--project-directory', str(self.root), '--env-file', str(self.root / '.env'), '-f', str(self.root / 'compose.yml')]
        # Dependency identity checks have their own metadata tests; these exercise actual Compose rendering.
        self.labCheckPatch = patch.object(ops, 'validate_lab_dependencies')
        self.labCheckPatch.start()
        self.addCleanup(self.labCheckPatch.stop)

    def test_real_compose_has_two_isolated_apps_and_no_public_backend_ports(self):
        config = ops.configuration(True)
        for service in ('app-a', 'app-b', 'helmet-a', 'helmet-b', 'belt-a', 'belt-b', 'wear-api', 'fuda-api', 'backend-router'):
            self.assertFalse(config['services'][service].get('ports'))
            if service != 'backend-router':
                self.assertEqual(len(config['services'][service]['tmpfs']), 1)
                self.assertTrue(config['services'][service]['tmpfs'][0].startswith('/tmp:size='))
                self.assertIn(',mode=1777', config['services'][service]['tmpfs'][0])
        self.assertEqual(config['services']['app-a']['environment']['LOGGING_CONFIG'], 'file:/config/logback-cluster.xml')
        self.assertIn('-Dlogback.configurationFile=/config/logback-cluster.xml', config['services']['app-a']['environment']['JAVA_TOOL_OPTIONS'])
        self.assertEqual(len(config['services']['ingress']['ports']), 1)
        self.assertEqual(config['services']['ingress']['ports'][0]['host_ip'], '127.0.0.1')
        for service in ('helmet-a', 'helmet-b', 'belt-a', 'belt-b'):
            mounts = config['services'][service]['volumes']
            self.assertTrue(any(v['target'] == f'/run/private/{service}.json' for v in mounts))
            self.assertFalse(any(v['target'] == '/run/private' for v in mounts))

    def test_entry_cannot_publish_private_services_or_fall_back_to_spring(self):
        config = ops.configuration(True)
        config['services']['wear-api']['ports'] = [{'published': 18088}]
        with self.assertRaisesRegex(ValueError, 'Only ingress'):
            ops.validate_entry(config['services'])
        del config['services']['wear-api']['ports']
        for target in ('backend:18084', 'app-a:18084', 'example.com:80', '8.8.8.8:80', 'pc-static:80 { injected }'):
            config['services']['ingress']['environment']['PC_STATIC_UPSTREAM'] = target
            with self.assertRaises(ValueError):
                ops.validate_entry(config['services'])

    def test_local_file_probe_requires_matching_marker_and_leaves_no_temporary_files(self):
        root = self.root / 'shared' / 'files'
        store = '42bb991a-a149-4a82-94f3-62aca3b41fb1'
        with self.assertRaisesRegex(ValueError, 'identity'):
            ops.local_shared_probe(root, store)
        (root / '.wearable-store-id').write_bytes((store + '\n').encode('ascii'))
        ops.local_shared_probe(root, store)
        self.assertEqual([p.name for p in root.iterdir()], ['.wearable-store-id'])
        with self.assertRaisesRegex(ValueError, 'identity'):
            ops.local_shared_probe(root, '43bb991a-a149-4a82-94f3-62aca3b41fb1')
        with self.assertRaisesRegex(ValueError, 'identity'):
            ops.local_shared_probe(root, store.upper())
        for suffix in ('\r\n', '', '\n\n'):
            (root / '.wearable-store-id').write_bytes((store + suffix).encode('ascii'))
            with self.assertRaisesRegex(ValueError, 'identity'):
                ops.local_shared_probe(root, store)

    def test_store_initializer_refuses_noncanonical_existing_marker(self):
        spec = importlib.util.spec_from_file_location('prepare_shared_store', DEPLOY / 'prepare-shared-store.py')
        store_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(store_module)
        root = self.root / 'shared' / 'files'
        store = '42bb991a-a149-4a82-94f3-62aca3b41fb1'
        store_module.initialize(root, store)
        self.assertEqual((root / '.wearable-store-id').read_bytes(), (store + '\n').encode('ascii'))
        store_module.initialize(root, store)
        invalid = (store + '\r\n').encode('ascii')
        (root / '.wearable-store-id').write_bytes(invalid)
        with self.assertRaisesRegex(ValueError, 'differs'):
            store_module.initialize(root, store)
        self.assertEqual((root / '.wearable-store-id').read_bytes(), invalid)

    def test_duplicate_identity_and_floating_production_images_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'pinned'):
            ops.configuration(False)
        (self.root / '.lab.env').write_text(self.dotenv + 'CLUSTER_PROJECT=wearable-lab-test\nCLUSTER_NETWORK=wearable-lab-test\nNODE_B_ID=app-a\n')
        with self.assertRaisesRegex(ValueError, 'identity'):
            ops.configuration(True)

    def test_interrupted_or_mixed_gateway_generation_is_rejected(self):
        marker = self.root / 'private' / 'lab' / '.gateway-config.incomplete'
        marker.write_text('in progress')
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            ops.configuration(True)
        marker.unlink()
        (self.root / 'private' / 'lab' / 'Caddy.devices').write_text('# interrupted replacement\n')
        with self.assertRaisesRegex(ValueError, 'mixed'):
            ops.configuration(True)

    def test_generation_change_requires_complete_maintenance_window(self):
        ops.configuration(True)
        def responses(running, previous='old', exists=True):
            def fake(args, **kwargs):
                if '--services' in args:
                    return running
                if args[1] == 'inspect':
                    return previous
                self.assertIn('--all', args)
                return 'ingress-id' if exists and args[-1] == 'ingress' else ''
            return fake
        for running in ('app-a\nhelmet-a\ningress\n', 'app-a\n'):
            for exists in (True, False):
                with patch.object(ops, 'call', side_effect=responses(running, exists=exists)):
                    with self.assertRaisesRegex(ValueError, 'both node groups'):
                        ops.generation_window()
        with patch.object(ops, 'call', side_effect=responses('ingress\n')):
            ops.generation_window()
        with patch.object(ops, 'call', side_effect=responses('app-a\n', previous=os.environ['GATEWAY_CONFIG_GENERATION'])):
            ops.generation_window()

if __name__ == '__main__':
    unittest.main()
