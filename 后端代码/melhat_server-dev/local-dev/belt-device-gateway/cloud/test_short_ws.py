import contextlib
import io
import unittest
from unittest import mock

import deploy
import legacy_ws
import short_ws
import test_legacy_ws as legacy_tests


class ShortWsTests(unittest.TestCase):
    def setUp(self):
        legacy_tests.LegacyWsTests.setUp(self)
        self.patch.preview()
        self.patch.apply()
        self.legacy_bytes = {name: (self.legacy_state / name).read_bytes()
                             for name in ['patch-preview.json', 'patch-transaction.json']}
        self.before_short = self.caddy.read_bytes()
        self.short_state = self.root / 'short-ws-01'
        self.patch = short_ws.Patch(self.short_state, self.legacy_state, self.sni_state,
                                   self.alias_state, self.deployment_state)
        self.reload.reset_mock()
        self.run.reset_mock()
        self.http_health.reset_mock()

    def tearDown(self):
        legacy_tests.LegacyWsTests.tearDown(self)

    def assert_protected(self):
        legacy_tests.LegacyWsTests.assert_protected(self)
        for name, value in self.legacy_bytes.items():
            self.assertEqual(value, (self.legacy_state / name).read_bytes())

    def new_patch(self, name):
        return short_ws.Patch(self.root / name, self.legacy_state, self.sni_state,
                              self.alias_state, self.deployment_state)

    def test_candidate_changes_only_one_exact_matcher_preserving_every_other_byte(self):
        token = deploy.PLACEHOLDER_TOKEN.encode('ascii')
        before = self.before_short + b'\n# Preserve unrelated later comments byte-for-byte.\n'
        expected = before.replace(b'@belt_legacy_ws path /' + token + b'/wsHat\n',
                                  b'@belt_legacy_ws path /' + token + b'/wsHat /' + token[:24] + b'/wsHat\n', 1)
        after = short_ws.candidate(before)
        self.assertEqual(expected, after)
        self.assertEqual(32, len(after) - len(before))
        self.assertEqual(2, after.count(self.helmet_token.encode('ascii')))
        self.assertEqual(1, after.count(b'http://39.106.212.138 {'))
        self.assertNotIn(b'path /wsHat', after)
        self.assertNotIn(b'/' + token[:24] + b'/wsBelt', after)
        self.assertNotIn(b'/' + token[:24] + b'/api/', after)

    def test_malformed_duplicate_expanded_or_mismatched_legacy_blocks_are_rejected(self):
        token = deploy.PLACEHOLDER_TOKEN.encode('ascii')
        legacy = short_ws.BLOCK.search(self.before_short).group(0)
        wrong_token = ('A' if token[:1] != b'A' else 'B').encode('ascii') + token[1:]
        for invalid in [
            short_ws.candidate(self.before_short),
            self.before_short + legacy,
            self.before_short.replace(legacy_ws.END, b''),
            self.before_short.replace(legacy, legacy.replace(b':28087', b':28086')),
            self.before_short.replace(legacy, legacy.replace(b'/wsHat\n', b'/wsHat /*\n')),
            self.before_short.replace(legacy, legacy.replace(token, wrong_token)),
            self.before_short.replace(legacy, legacy.replace(b'respond 404', b'respond 200')),
        ]:
            with self.assertRaises(deploy.DeployError):
                short_ws.candidate(invalid)

    def test_success_repeat_and_rollback_preserve_previous_journals_inode_and_stdout_privacy(self):
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            self.patch.preview()
            preview = (self.short_state / 'patch-preview.json').read_bytes()
            self.patch.preview()
            self.assertEqual(preview, (self.short_state / 'patch-preview.json').read_bytes())
            self.assertEqual({'patch', 'legacy', 'sni', 'alias', 'helper'}, set(self.patch.load()['scripts']))
            self.patch.apply()
            self.assertEqual(short_ws.candidate(self.before_short), self.caddy.read_bytes())
            self.assertEqual(1, self.reload.call_count)
            self.http_health.assert_called_once_with()
            self.patch.apply()
            self.assertEqual(1, self.reload.call_count)
            self.assert_protected()
            self.patch.rollback()
            self.patch.rollback()
        self.assertEqual(self.before_short, self.caddy.read_bytes())
        self.assertEqual('rolled-back', deploy.load_json(self.patch.journal)['status'])
        self.assertNotIn(deploy.PLACEHOLDER_TOKEN, stdout.getvalue())
        self.assertNotIn(deploy.PLACEHOLDER_TOKEN[:24], stdout.getvalue())
        self.assert_protected()
        for call in self.run.call_args_list:
            self.assertEqual(['docker', 'exec', '-i', deploy.CONTAINER, 'caddy', 'validate'], call[0][2][:6])

    def test_legacy_must_be_applied_and_active_configuration_must_match(self):
        journal = self.legacy_state / 'patch-transaction.json'
        transaction = deploy.load_json(journal)
        deploy.save_json(journal, dict(transaction, status='rolled-back'))
        with self.assertRaises(deploy.DeployError):
            self.patch.preview()
        journal.write_bytes(self.legacy_bytes['patch-transaction.json'])
        self.caddy.write_bytes(self.before_short + b'\n# external change\n')
        with self.assertRaises(deploy.DeployError):
            self.patch.preview()
        self.reload.assert_not_called()

    def test_changed_chain_and_protected_resources_prevent_apply(self):
        self.patch.preview()
        for path in [self.legacy_state / 'patch-transaction.json', self.sni_state / 'patch-transaction.json',
                     self.alias_state / 'patch-transaction.json', self.deployment_state / 'deployment.json',
                     self.sshd, self.key_file]:
            saved = path.read_bytes()
            path.write_bytes(saved + b'\n')
            with self.assertRaises(deploy.DeployError):
                self.patch.apply()
            path.write_bytes(saved)
        self.assertEqual(self.before_short, self.caddy.read_bytes())
        self.reload.assert_not_called()
        self.assert_protected()

    def test_validation_failure_does_not_write_active_file_or_transaction(self):
        self.patch.preview()
        self.run.side_effect = deploy.DeployError('validation failed')
        with self.assertRaises(deploy.DeployError):
            self.patch.apply()
        self.assertFalse(self.patch.journal.exists())
        self.assertEqual(self.before_short, self.caddy.read_bytes())
        self.reload.assert_not_called()
        self.assert_protected()

    def test_reload_failure_and_final_journal_failure_restore_configuration(self):
        self.patch.preview()
        self.reload.side_effect = [deploy.DeployError('reload failed'), None]
        with self.assertRaisesRegex(deploy.DeployError, 'restored and reloaded'):
            self.patch.apply()
        self.assertEqual(self.before_short, self.caddy.read_bytes())
        self.assert_protected()
        self.reload.side_effect = None
        second = self.new_patch('short-ws-02')
        second.preview()
        save = deploy.save_json
        def fail_applied(path, value):
            if path == second.journal and value.get('status') == 'applied':
                raise deploy.DeployError('journal failure')
            return save(path, value)
        with mock.patch.object(deploy, 'save_json', side_effect=fail_applied):
            with self.assertRaisesRegex(deploy.DeployError, 'restored and reloaded'):
                second.apply()
        self.assertEqual(self.before_short, self.caddy.read_bytes())
        self.assertEqual('rolled-back', deploy.load_json(second.journal)['status'])
        self.assert_protected()

    def test_failed_rollback_reload_can_be_retried_without_overwriting_later_changes(self):
        self.patch.preview()
        self.reload.side_effect = deploy.DeployError('reload failed')
        with self.assertRaisesRegex(deploy.DeployError, 'restoration needs attention'):
            self.patch.apply()
        self.assertEqual(self.before_short, self.caddy.read_bytes())
        self.reload.side_effect = None
        self.patch.rollback()
        later = self.before_short + b'\n# another operator\n'
        self.caddy.write_bytes(later)
        with self.assertRaisesRegex(deploy.DeployError, 'later changes were not overwritten'):
            self.patch.rollback()
        self.assertEqual(later, self.caddy.read_bytes())
        self.assert_protected()

    def test_prepared_transaction_resumes_after_write_without_duplicate_route(self):
        self.patch.preview()
        plan = self.patch.load()
        deploy.save_json(self.patch.journal, {'kind': short_ws.KIND, 'status': 'prepared',
                                             'afterSha256': plan['afterSha256']})
        self.caddy.write_bytes((self.short_state / 'after.Caddyfile').read_bytes())
        self.patch.apply()
        self.assertEqual(short_ws.candidate(self.before_short), self.caddy.read_bytes())
        self.assertEqual('applied', deploy.load_json(self.patch.journal)['status'])
        self.assert_protected()

    def test_health_failure_rolls_back_to_previous_legacy_route(self):
        self.patch.preview()
        self.http_health.side_effect = [deploy.DeployError('health check failed'), None]
        with self.assertRaisesRegex(deploy.DeployError, 'restored and reloaded'):
            self.patch.apply()
        self.assertEqual(self.before_short, self.caddy.read_bytes())
        self.assertEqual('rolled-back', deploy.load_json(self.patch.journal)['status'])
        self.assert_protected()

    def test_state_directories_are_separate_and_changed_scripts_prevent_apply(self):
        for state in [self.legacy_state, self.sni_state, self.alias_state, self.deployment_state,
                      self.legacy_state / 'child', self.root]:
            with self.assertRaises(deploy.DeployError):
                short_ws.Patch(state, self.legacy_state, self.sni_state, self.alias_state, self.deployment_state)
        self.patch.preview()
        with mock.patch.object(short_ws, 'script_hashes', return_value={}):
            with self.assertRaisesRegex(deploy.DeployError, 'scripts changed'):
                self.patch.apply()
        self.reload.assert_not_called()
        self.assert_protected()

    def test_candidate_tampering_is_rejected_before_apply(self):
        self.patch.preview()
        after = self.short_state / 'after.Caddyfile'
        after.write_bytes(after.read_bytes() + b'\n# tampered candidate\n')
        with self.assertRaisesRegex(deploy.DeployError, 'integrity check failed'):
            self.patch.apply()
        self.assertEqual(self.before_short, self.caddy.read_bytes())
        self.reload.assert_not_called()


if __name__ == '__main__':
    unittest.main()
