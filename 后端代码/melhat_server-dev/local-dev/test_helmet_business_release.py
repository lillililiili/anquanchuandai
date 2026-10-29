"""Offline release-plan checks. No Docker, database or running service is contacted."""
import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('helmet_release', pathlib.Path(__file__).with_name('helmet-business-release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

class ReleaseChecks(unittest.TestCase):
    def test_qa_options_replace_live_integration_and_redis_options(self):
        options = release.override_options(['--spring.redis.host=live', '--spring.redis.database=10', '--melhat.direct.enabled=true', '--melhat.direct.enabled=false', '--keep=value'],
            {'--spring.redis.host':'qa-only', '--spring.redis.database':'0', '--melhat.direct.enabled':'false'})
        self.assertEqual(options.count('--melhat.direct.enabled=false'), 1)
        self.assertNotIn('--melhat.direct.enabled=true', options)
        self.assertNotIn('--spring.redis.host=live', options)
        self.assertNotIn('--spring.redis.database=10', options)
        self.assertIn('--keep=value', options)

    def test_admin_ledger_is_not_misrepresented_as_a_json_backup(self):
        self.assertNotIn('wearable-admin.json', release.STATE_FILES)
        calls = []
        with tempfile.TemporaryDirectory() as folder, patch.object(release, 'run', side_effect=lambda *args: calls.append(args)):
            copied = release.copy_state('live-backend', pathlib.Path(folder))
            release.restore_state('previous-backend', pathlib.Path(folder), copied)
        self.assertEqual(copied, ['guardian-state.json','helmet-media-private.json'])
        self.assertTrue(all(call[0] == 'cp' for call in calls))
        self.assertTrue(all('previous-backend:/data/' in call[-1] for call in calls[2:]))

    def test_missing_primary_snapshot_aborts_and_optional_new_journal_is_allowed(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(release, 'run', side_effect=RuntimeError('missing')):
                with self.assertRaises(RuntimeError):
                    release.copy_state('live-backend', pathlib.Path(folder))
            def optional(*args):
                if 'helmet-media-private.json' in args[1]:
                    raise RuntimeError('not deployed yet')
            with patch.object(release, 'run', side_effect=optional):
                self.assertEqual(release.copy_state('live-backend', pathlib.Path(folder)), ['guardian-state.json'])

    def test_restore_refuses_unexpected_paths(self):
        with patch.object(release, 'run') as run:
            with self.assertRaises(RuntimeError):
                release.restore_state('previous-backend', pathlib.Path('/backup'), ['../outside'])
            run.assert_not_called()

if __name__ == '__main__':
    unittest.main()
