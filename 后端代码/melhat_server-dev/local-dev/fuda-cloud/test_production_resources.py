"""Offline Compose parsing and guard mutation tests; no container/daemon operations."""
import copy
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

import production_resources_check as check

HERE = Path(__file__).resolve().parent


class ProductionResourceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        files = ['compose.yml', 'compose.production.yml']
        cls.baseline = check.parse_config(files, HERE / '.env.example')
        cls.merged = check.parse_config(files + [check.OVERLAY], HERE / '.env.example')

    def changed(self):
        return copy.deepcopy(self.merged)

    def test_full_production_merge_is_bounded_and_draft_only(self):
        report = check.validate(self.baseline, self.merged)
        self.assertTrue(report['configurationPassed'])
        self.assertEqual(2080, report['totalMemoryLimitMiB'])
        self.assertFalse(report['runtimeValidated'])
        self.assertTrue(report['productionPreflightStillRequired'])

    def test_missing_production_overlay_cannot_supply_gateway_definitions(self):
        # Resource-only declarations intentionally have no build/image/profile.
        with self.assertRaises(check.ResourceValidationError):
            check.parse_config(['compose.yml', check.OVERLAY], HERE / '.env.example')

    def test_staging_or_renamed_project_is_rejected(self):
        for name in ('fuda-wearables-staging', 'arbitrary-production'):
            with self.subTest(project=name):
                cfg = self.changed(); cfg['name'] = name
                with self.assertRaises(check.ResourceValidationError):
                    check.validate(self.baseline, cfg)

    def test_missing_role_cutover_profile_or_private_runtime_is_rejected(self):
        for attack in ('role', 'profile', 'runtime'):
            with self.subTest(attack=attack):
                cfg = self.changed()
                if attack == 'role':
                    cfg['services']['backend']['labels']['com.wearables.deployment-role'] = 'staging'
                elif attack == 'profile':
                    cfg['services']['helmet-gateway'].pop('profiles')
                else:
                    v = next(v for v in cfg['services']['backend']['volumes'] if v['target'].endswith('device-runtime.yml'))
                    v['source'] = '/unsafe/safe-runtime.yml'
                with self.assertRaises(check.ResourceValidationError):
                    check.validate(self.baseline, cfg)

    def test_public_database_backend_or_query_binding_is_rejected(self):
        for service in ('mysql', 'redis', 'backend', 'query-gateway'):
            with self.subTest(service=service):
                cfg = self.changed()
                if service in ('mysql', 'redis'):
                    cfg['services'][service]['ports'] = [{'host_ip': '0.0.0.0', 'published': '3306', 'target': 3306}]
                else:
                    cfg['services'][service]['ports'][0]['host_ip'] = '0.0.0.0'
                with self.assertRaises(check.ResourceValidationError):
                    check.validate(self.baseline, cfg)

    def test_database_egress_or_host_mode_is_rejected(self):
        for attack in ('egress', 'host'):
            cfg = self.changed()
            if attack == 'egress': cfg['services']['mysql']['networks']['egress'] = None
            else: cfg['services']['mysql']['network_mode'] = 'host'
            with self.assertRaises(check.ResourceValidationError):
                check.validate(self.baseline, cfg)

    def test_unbounded_memory_swap_or_new_cpu_quota_is_rejected(self):
        for field, value in (('mem_limit', 0), ('memswap_limit', -1), ('cpus', 0.5)):
            with self.subTest(field=field):
                cfg = self.changed(); cfg['services']['backend'][field] = value
                with self.assertRaises(check.ResourceValidationError):
                    check.validate(self.baseline, cfg)

    def test_redis_eviction_disabled_aof_or_literal_password_is_rejected(self):
        command = self.merged['services']['redis']['command'][-1]
        for before, after in (('--appendonly yes', '--appendonly no'),
                              ('--appendfsync always', '--appendfsync everysec'),
                              ('noeviction', 'allkeys-lru'),
                              ('REDIS_PASSWORD', 'OTHER_PASSWORD')):
            with self.subTest(change=before):
                cfg = self.changed(); cfg['services']['redis']['command'][-1] = command.replace(before, after)
                with self.assertRaises(check.ResourceValidationError):
                    check.validate(self.baseline, cfg)

    def test_changed_business_profile_credentials_or_device_switch_is_rejected(self):
        for key, value in (('SPRING_PROFILES_ACTIVE', 'prod'),
                           ('SPRING_DATASOURCE_DRUID_MASTER_PASSWORD', 'not-the-original'),
                           ('MELHAT_DIRECT_ENABLED', 'true')):
            with self.subTest(key=key):
                cfg = self.changed(); cfg['services']['backend']['environment'][key] = value
                with self.assertRaises(check.ResourceValidationError):
                    check.validate(self.baseline, cfg)

    def test_changed_images_volume_paths_or_logging_are_rejected(self):
        for attack in ('image', 'volume', 'logging'):
            cfg = self.changed()
            if attack == 'image': cfg['services']['backend']['image'] = 'unexpected:latest'
            elif attack == 'volume': cfg['volumes']['mysql-data']['name'] = 'production-existing-data'
            else: cfg['services']['backend']['logging']['options']['max-file'] = '100'
            with self.assertRaises(check.ResourceValidationError):
                check.validate(self.baseline, cfg)

    def test_parser_never_invokes_up_build_exec_or_inherits_compose_override(self):
        completed = subprocess.CompletedProcess([], 0, b'{}', b'')
        with patch.dict(os.environ, {'COMPOSE_FILE': 'unsafe.yml', 'DOCKER_HOST': 'tcp://untrusted:2375'}), \
                patch.object(check.subprocess, 'run', return_value=completed) as run:
            check.parse_config(['compose.yml'], HERE / '.env.example')
            args, kwargs = run.call_args
            self.assertIn('config', args[0])
            self.assertTrue({'up', 'build', 'start', 'exec', 'stop'}.isdisjoint(args[0]))
            self.assertNotIn('COMPOSE_FILE', kwargs['env'])
            self.assertNotIn('DOCKER_HOST', kwargs['env'])

    def test_compose_error_does_not_expose_raw_private_output(self):
        completed = subprocess.CompletedProcess([], 1, b'PRIVATE_CREDENTIAL_SENTINEL', b'PRIVATE_CREDENTIAL_SENTINEL')
        with patch.object(check.subprocess, 'run', return_value=completed):
            with self.assertRaises(check.ResourceValidationError) as caught:
                check.parse_config(['compose.yml'], HERE / '.env.example')
        self.assertNotIn('PRIVATE_CREDENTIAL_SENTINEL', str(caught.exception))


if __name__ == '__main__':
    unittest.main()
