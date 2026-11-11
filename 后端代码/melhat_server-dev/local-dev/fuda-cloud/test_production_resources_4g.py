"""Offline Compose/host-evidence tests. No containers, routes or services change."""
import copy
import unittest

import production_resources_4g_check as check
import production_resources_check as common


def host_samples():
    return [{'monotonicSeconds': float(t), 'linuxHost': True, 'cpuCount': 2,
             'availableMemoryBytes': 2400 * 1024 ** 2, 'freeDiskBytes': 20 * 1024 ** 3,
             'swapUsedBytes': 130 * 1024 ** 2, 'swapInPages': 100, 'swapOutPages': 200,
             'pageSizeBytes': 4096} for t in range(0, 301, 10)]


class DedicatedProductionConfigTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        files = ['compose.yml', 'compose.production.yml']
        cls.baseline = common.parse_config(files, check.HERE / '.env.example')
        cls.candidate = common.parse_config(files + [check.OVERLAY], check.HERE / '.env.example')

    def test_budget_everysec_persistence_and_trial_scope(self):
        report = check.validate_config(self.baseline, self.candidate)
        self.assertEqual(1888, report['totalMemoryLimitMiB'])
        self.assertEqual(512, report['additionalAvailableMemoryReserveMiB'])
        self.assertEqual('everysec', report['redisAofFsync'])
        self.assertTrue(report['trialOnly'])
        self.assertFalse(report['productionReady'])
        self.assertFalse(report['runtimeValidated'])
        self.assertFalse(report['cpuQuotasAdded'])

    def test_staging_missing_production_and_unselected_8g_are_rejected(self):
        with self.assertRaises(common.ResourceValidationError):
            common.parse_config(['compose.yml', check.OVERLAY], check.HERE / '.env.example')
        wrong = copy.deepcopy(self.candidate); wrong['name'] = 'fuda-wearables-staging'
        with self.assertRaises(common.ResourceValidationError):
            check.validate_config(self.baseline, wrong)
        eight = common.parse_config(['compose.yml', 'compose.production.yml', common.OVERLAY], check.HERE / '.env.example')
        with self.assertRaises(common.ResourceValidationError):
            check.validate_config(self.baseline, eight)

    def test_existing_jvm_option_sources_are_not_silently_overwritten(self):
        for source in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS'):
            with self.subTest(source=source):
                before = copy.deepcopy(self.baseline)
                before['services']['backend']['environment'][source] = '-Dexisting=value'
                with self.assertRaises(common.ResourceValidationError):
                    check.validate_config(before, self.candidate)

    def test_memory_cpu_swap_or_business_profile_change_is_rejected(self):
        for attack in ('memory', 'cpu', 'swap', 'profile'):
            with self.subTest(attack=attack):
                cfg = copy.deepcopy(self.candidate); service = cfg['services']['backend']
                if attack == 'memory': service['mem_limit'] = 1024 * 1024 ** 2
                elif attack == 'cpu': service['cpus'] = 0.5
                elif attack == 'swap': service['memswap_limit'] = -1
                else: service['environment']['SPRING_PROFILES_ACTIVE'] = 'prod'
                with self.assertRaises(common.ResourceValidationError):
                    check.validate_config(self.baseline, cfg)

    def test_public_backend_database_or_host_database_is_rejected(self):
        for attack in ('backend', 'mysql', 'redis'):
            cfg = copy.deepcopy(self.candidate)
            if attack == 'backend': cfg['services'][attack]['ports'][0]['host_ip'] = '0.0.0.0'
            elif attack == 'mysql': cfg['services'][attack]['ports'] = [{'host_ip': '0.0.0.0', 'published': '3306', 'target': 3306}]
            else: cfg['services'][attack]['network_mode'] = 'host'
            with self.assertRaises(common.ResourceValidationError):
                check.validate_config(self.baseline, cfg)

    def test_redis_no_fsync_each_write_no_eviction_and_no_password_change(self):
        for before, after in (('everysec', 'always'), ('--appendonly yes', '--appendonly no'),
                              ('noeviction', 'allkeys-lru'), ('REDIS_PASSWORD', 'OTHER_PASSWORD')):
            cfg = copy.deepcopy(self.candidate)
            cfg['services']['redis']['command'][-1] = cfg['services']['redis']['command'][-1].replace(before, after)
            with self.assertRaises(common.ResourceValidationError):
                check.validate_config(self.baseline, cfg)


class TrialHostAdmissionTest(unittest.TestCase):
    def test_exact_five_minute_threshold_accepts_existing_stable_swap_usage(self):
        report = check.evaluate_host_window(host_samples())
        self.assertTrue(report['trialHostAdmissionPassed'])
        self.assertEqual(130, report['maximumSwapUsedMiB'])
        self.assertFalse(report['productionReady'])

    def test_single_snapshot_short_window_or_gap_is_not_stability_proof(self):
        with self.assertRaises(common.ResourceValidationError):
            check.evaluate_host_window(host_samples()[:1])
        self.assertFalse(check.evaluate_host_window(host_samples()[:-1])['trialHostAdmissionPassed'])
        samples = host_samples(); del samples[15]
        self.assertFalse(check.evaluate_host_window(samples)['trialHostAdmissionPassed'])

    def test_memory_or_disk_dip_even_one_sample_rejects_trial_admission(self):
        for key in ('availableMemoryBytes', 'freeDiskBytes'):
            samples = host_samples(); samples[15][key] -= 1
            self.assertFalse(check.evaluate_host_window(samples)['trialHostAdmissionPassed'])

    def test_wrong_os_or_too_few_cpus_is_rejected(self):
        for key, value in (('linuxHost', False), ('cpuCount', 1)):
            samples = host_samples(); samples[1][key] = value
            self.assertFalse(check.evaluate_host_window(samples)['trialHostAdmissionPassed'])

    def test_thirty_seconds_of_swap_pressure_is_rejected(self):
        samples = host_samples()
        for i, row in enumerate(samples):
            row['swapInPages'] += min(i, 3) * 2560  # 1 MiB/s over 10 seconds.
        report = check.evaluate_host_window(samples)
        self.assertFalse(report['trialHostAdmissionPassed'])
        self.assertEqual(30, report['longestHighSwapSeconds'])

    def test_one_short_swap_burst_is_recorded_without_claiming_sustained_pressure(self):
        samples = host_samples()
        for row in samples[1:]: row['swapInPages'] += 2560
        report = check.evaluate_host_window(samples)
        self.assertTrue(report['trialHostAdmissionPassed'])
        self.assertEqual(10, report['longestHighSwapSeconds'])

    def test_counter_reset_duplicate_time_nonfinite_values_rejected(self):
        for key, value in (('swapInPages', 1), ('monotonicSeconds', 0),
                           ('availableMemoryBytes', float('inf')), ('pageSizeBytes', 0)):
            samples = host_samples(); samples[1][key] = value
            with self.assertRaises(common.ResourceValidationError):
                check.evaluate_host_window(samples)


if __name__ == '__main__':
    unittest.main()
