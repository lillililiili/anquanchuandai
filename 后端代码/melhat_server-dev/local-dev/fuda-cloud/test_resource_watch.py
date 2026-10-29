import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('watch', HERE / 'resource-watch.py')
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)


def container(service='backend', project=watch.PROJECT, limited=True, identifier='a' * 64):
    memory, cpu = watch.CAPS.get(service, (1024, 0.1))
    return {'Id': identifier, 'Config': {'Labels': {'com.docker.compose.project': project,
        'com.docker.compose.service': service, watch.LIMIT_LABEL: 'true' if limited else 'false'}},
        'State': {'Running': True, 'Status': 'running'}, 'RestartCount': 0,
        'HostConfig': {'Memory': memory, 'MemorySwap': memory, 'NanoCpus': int(cpu * 1000000000), 'RestartPolicy': {'Name': 'no'}}}


def sample():
    return {'host': {'availableMemoryBytes': 1800 * watch.MIB, 'swapUsedBytes': 116 * watch.MIB,
        'swapInPages': 0, 'swapOutPages': 0, 'pageSizeBytes': 4096,
        'freeDiskBytes': 20 * 1024 ** 3}, 'staging': [],
        'other': {'original': {'running': True, 'health': 'healthy', 'restartCount': 2}}}


class GuardTest(unittest.TestCase):
    def test_low_memory_requires_duration_and_recovers(self):
        first = sample(); guard = watch.Thresholds(first); current = copy.deepcopy(first)
        current['host']['availableMemoryBytes'] = 500 * watch.MIB
        self.assertEqual([], guard.evaluate(current, 1))
        self.assertEqual([], guard.evaluate(current, 30))
        self.assertIn('host_memory_below_512MiB_for_30s', guard.evaluate(current, 31))
        self.assertEqual([], guard.evaluate(first, 32))
        self.assertEqual([], guard.evaluate(current, 33))

    def test_critical_memory_and_swap_growth_are_immediate(self):
        first = sample(); current = copy.deepcopy(first); guard = watch.Thresholds(first)
        current['host']['availableMemoryBytes'] = 255 * watch.MIB
        current['host']['swapUsedBytes'] += 129 * watch.MIB
        issues = guard.evaluate(current, 0)
        self.assertIn('host_memory_below_256MiB', issues)
        self.assertIn('host_swap_growth_above_128MiB', issues)

    def test_small_continuous_swap_does_not_stop_healthy_stack(self):
        first = sample(); guard = watch.Thresholds(first); current = copy.deepcopy(first)
        guard.evaluate(first, 233.8)
        for index in range(1, 10):
            current['host']['swapInPages'] += 1
            current['host']['swapOutPages'] += 64
            self.assertEqual([], guard.evaluate(current, 233.8 + index * 5.1))
            self.assertLess(guard.last_swap_bytes_per_second, watch.MIB)

    def test_sustained_combined_high_swap_rate_uses_actual_page_size(self):
        first = sample(); first['host']['pageSizeBytes'] = 65536
        guard = watch.Thresholds(first); current = copy.deepcopy(first)
        guard.evaluate(first, 100)
        for elapsed in range(5, 31, 5):
            # Each direction is only 0.5 MiB/s; their combined 1 MiB/s is the threshold.
            current['host']['swapInPages'] += 40
            current['host']['swapOutPages'] += 40
            issues = guard.evaluate(current, 100 + elapsed)
            self.assertEqual(watch.MIB, guard.last_swap_bytes_per_second)
            if elapsed < 30:
                self.assertNotIn('host_swap_io_ge_1MiBps_for_30s', issues)
        self.assertIn('host_swap_io_ge_1MiBps_for_30s', issues)
        self.assertNotIn('host_swap_io_ge_1MiBps_for_30s', guard.evaluate(current, 135))

    def test_swap_rate_uses_observed_interval_and_resets_after_low_rate(self):
        first = sample(); guard = watch.Thresholds(first); current = copy.deepcopy(first)
        guard.evaluate(first, 0)
        for second in (5, 10, 15, 20, 25):
            current['host']['swapOutPages'] += 1280
            self.assertEqual([], guard.evaluate(current, second))
        # Same page delta over 10 seconds is 0.5 MiB/s, breaking the sustained period.
        current['host']['swapOutPages'] += 1280
        self.assertEqual([], guard.evaluate(current, 35))
        self.assertEqual(watch.MIB / 2, guard.last_swap_bytes_per_second)
        for second in (40, 45, 50, 55, 60):
            current['host']['swapOutPages'] += 1280
            self.assertEqual([], guard.evaluate(current, second))
        current['host']['swapOutPages'] += 1280
        self.assertIn('host_swap_io_ge_1MiBps_for_30s', guard.evaluate(current, 65))

    def test_host_observes_real_system_page_size(self):
        with patch.object(watch.Path, 'read_text', side_effect=[
            'MemAvailable: 1800000 kB\nSwapTotal: 2097152 kB\nSwapFree: 2097152 kB\n',
            'pswpin 10\npswpout 20\n']), patch.object(watch.os, 'sysconf', return_value=65536, create=True) as page_size, patch.object(watch.os, 'getloadavg', return_value=(0, 0, 0), create=True), patch.object(watch.shutil, 'disk_usage') as disk:
            disk.return_value.free = 20 * 1024 ** 3
            observed = watch.host_state(HERE)
            self.assertEqual(65536, observed['pageSizeBytes'])
            page_size.assert_called_once_with('SC_PAGE_SIZE')

    def test_initial_valid_stopped_container_can_start_but_later_exit_stops(self):
        first = sample(); first['staging'] = [{'id': 'a' * 64, 'service': 'backend',
            'running': False, 'oomKilled': False, 'status': 'exited', 'health': None, 'capIssues': []}]
        guard = watch.Thresholds(first)
        self.assertEqual([], guard.evaluate(first, 10))
        self.assertEqual([], guard.evaluate(first, 129))
        running = copy.deepcopy(first); running['staging'][0].update(running=True, status='running')
        self.assertEqual([], guard.evaluate(running, 129.5))
        self.assertIn('staging_process_exited', guard.evaluate(first, 130))

    def test_initial_stopped_startup_timeout_is_120_seconds(self):
        first = sample(); first['staging'] = [{'id': 'a' * 64, 'service': 'backend',
            'running': False, 'oomKilled': False, 'status': 'exited', 'health': None, 'capIssues': []}]
        guard = watch.Thresholds(first)
        self.assertEqual([], guard.evaluate(first, 10))
        self.assertEqual([], guard.evaluate(first, 129.9))
        self.assertIn('initial_staging_startup_timeout_120s', guard.evaluate(first, 130))

    def test_only_initial_valid_exited_container_ignores_stale_unhealthy(self):
        first = sample(); first['staging'] = [{'id': 'a' * 64, 'service': 'mysql',
            'running': False, 'oomKilled': False, 'status': 'exited', 'health': 'unhealthy', 'capIssues': []}]
        guard = watch.Thresholds(first)
        self.assertEqual([], guard.evaluate(first, 0))
        self.assertEqual([], guard.evaluate(first, 119))
        running = copy.deepcopy(first); running['staging'][0].update(running=True, status='running')
        self.assertIn('staging_unhealthy', guard.evaluate(running, 119.5))
        issues = guard.evaluate(first, 119.9)
        self.assertIn('staging_unhealthy', issues)
        self.assertIn('staging_process_exited', issues)

    def test_stale_unhealthy_exception_does_not_cover_new_or_invalid_stops(self):
        first = sample(); stopped = copy.deepcopy(first)
        stopped['staging'] = [{'id': 'a' * 64, 'service': 'mysql', 'running': False,
            'oomKilled': False, 'status': 'exited', 'health': 'unhealthy', 'capIssues': []}]
        self.assertIn('staging_unhealthy', watch.Thresholds(first).evaluate(stopped, 0))
        stopped['staging'][0]['capIssues'] = ['swap_not_disabled']
        self.assertIn('staging_unhealthy', watch.Thresholds(stopped).evaluate(stopped, 0))

    def test_initial_waiting_unhealthy_non_exited_state_is_not_exempt(self):
        first = sample(); first['staging'] = [{'id': 'a' * 64, 'service': 'mysql',
            'running': False, 'oomKilled': False, 'status': 'exited', 'health': 'unhealthy', 'capIssues': []}]
        guard = watch.Thresholds(first); current = copy.deepcopy(first)
        current['staging'][0]['status'] = 'dead'
        self.assertIn('staging_unhealthy', guard.evaluate(current, 0))

    def test_initial_stopped_container_with_wrong_limits_has_no_grace(self):
        first = sample(); first['staging'] = [{'id': 'a' * 64, 'service': 'backend',
            'running': False, 'oomKilled': False, 'status': 'exited', 'health': None,
            'capIssues': ['swap_not_disabled']}]
        issues = watch.Thresholds(first).evaluate(first, 10)
        self.assertIn('staging_limit_or_ownership_mismatch', issues)
        self.assertIn('staging_process_exited', issues)

    def test_existing_service_regression_detected(self):
        first = sample(); current = copy.deepcopy(first); guard = watch.Thresholds(first)
        current['other']['original']['health'] = 'unhealthy'
        self.assertIn('existing_service_health_degraded', guard.evaluate(current, 0))
        current['other']['original']['restartCount'] += 1
        self.assertIn('existing_service_stopped_or_restarted', guard.evaluate(current, 1))

    def test_duplicate_service_is_outside_fixed_four_container_scope(self):
        first = sample(); guard = watch.Thresholds(first); current = copy.deepcopy(first)
        current['staging'] = [{'id': key, 'service': 'backend', 'running': True, 'oomKilled': False, 'status': 'running', 'health': None, 'capIssues': []} for key in ('a', 'b')]
        self.assertIn('duplicate_staging_service_exceeds_rehearsal_scope', guard.evaluate(current, 0))

    def test_staging_oom_or_exit_triggers_guard(self):
        first = sample(); guard = watch.Thresholds(first); current = copy.deepcopy(first)
        current['staging'] = [{'id': 'a', 'running': False, 'oomKilled': True, 'status': 'exited', 'health': None, 'capIssues': []}]
        self.assertIn('staging_oom', guard.evaluate(current, 0))
        self.assertIn('staging_process_exited', guard.evaluate(current, 0))

    def test_limits_are_real_hard_limits(self):
        c = container(); self.assertEqual([], watch.cap_issues(c))
        c['HostConfig']['MemorySwap'] *= 2
        self.assertIn('swap_not_disabled', watch.cap_issues(c))
        c['HostConfig']['Memory'] = 0
        self.assertIn('memory_limit_missing_or_too_high', watch.cap_issues(c))
        c['HostConfig']['NanoCpus'] = 0
        self.assertIn('cpu_limit_missing_or_too_high', watch.cap_issues(c))

    def test_host_must_confirm_swap_memory_and_cpu_limits(self):
        with patch.object(watch, 'docker', return_value=b'{"MemoryLimit":true,"SwapLimit":false,"CpuCfsQuota":true}'):
            capabilities = watch.limit_capabilities()
            self.assertTrue(capabilities['memoryLimitSupported'])
            self.assertFalse(capabilities['swapLimitSupported'])
            self.assertTrue(capabilities['cpuQuotaSupported'])

    def test_stop_cannot_target_production_original_or_unlabelled_staging(self):
        candidate = container(); original = container(project='knowledge', identifier='b' * 64)
        production = container(project='fuda-wearables-production', identifier='c' * 64)
        unlabelled = container(limited=False, identifier='d' * 64)
        unexpected = container(service='another-service', identifier='e' * 64)
        with patch.object(watch, 'inspect_all', return_value=[candidate, original, production, unlabelled, unexpected]), patch.object(watch, 'docker') as run:
            self.assertEqual(['a' * 12], watch.stop_owned())
            run.assert_called_once_with(['stop', '--time', '8', 'a' * 64])

    def test_no_mutation_if_no_proven_owned_container(self):
        with patch.object(watch, 'inspect_all', return_value=[container(project='production')]), patch.object(watch, 'docker') as run:
            self.assertEqual([], watch.stop_owned()); run.assert_not_called()

    def test_sample_mode_is_read_only(self):
        with patch('sys.argv', ['resource-watch.py', '--sample']), patch.object(watch.platform, 'system', return_value='Linux'), patch.object(watch, 'observe', return_value=sample()), patch.object(watch, 'stop_owned') as stop, patch('sys.stdout', new_callable=io.StringIO):
            self.assertEqual(0, watch.main()); stop.assert_not_called()

    def test_public_output_omits_original_details(self):
        current = sample(); current['other']['original']['Env'] = ['SECRET=value']
        value = json.dumps(watch.public_sample(current))
        self.assertNotIn('SECRET', value); self.assertNotIn('original', value)


class LimitedComposeTest(unittest.TestCase):
    def test_limited_overlay_keeps_staging_isolated_and_bounded(self):
        env = dict(os.environ)
        for key in ('COMPOSE_PROJECT_NAME', 'COMPOSE_FILE', 'COMPOSE_PROFILES'):
            env.pop(key, None)
        result = subprocess.run(['docker', 'compose', '--env-file', '.env.example', '-f', 'compose.yml', '-f', 'compose.rehearsal-limited.yml', 'config', '--no-env-resolution', '--format', 'json'], cwd=str(HERE), env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        config = json.loads(result.stdout.decode('utf-8'))
        self.assertEqual(watch.PROJECT, config['name'])
        self.assertEqual(set(watch.CAPS), set(config['services']))
        for name, (memory, cpu) in watch.CAPS.items():
            service = config['services'][name]
            self.assertEqual(memory, int(service['mem_limit'])); self.assertEqual(memory, int(service['memswap_limit']))
            self.assertAlmostEqual(cpu, float(service['cpus'])); self.assertEqual('no', service['restart'])
            self.assertEqual('true', service['labels'][watch.LIMIT_LABEL])
        backend = config['services']['backend']
        self.assertFalse(backend.get('ports')); self.assertEqual({'private'}, set(backend['networks']))
        self.assertIn('--melhat.direct.enabled=false', backend['command'])
        self.assertIn('-Xmx256m', backend['environment']['JAVA_TOOL_OPTIONS'])


if __name__ == '__main__':
    unittest.main()
