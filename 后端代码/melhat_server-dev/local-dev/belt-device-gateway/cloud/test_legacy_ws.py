import unittest
from unittest import mock

import deploy
import route_alias
import default_sni
import legacy_ws
import test_default_sni as sni_tests


class LegacyWsTests(unittest.TestCase):
    def setUp(self):
        sni_tests.DefaultSniTests.setUp(self)
        self.patch.preview()
        self.patch.apply()
        self.sni_bytes = {name: (self.sni_state / name).read_bytes()
                          for name in ['patch-preview.json', 'patch-transaction.json']}
        self.before_legacy = self.caddy.read_bytes()
        self.legacy_state = self.root / 'legacy-ws-patch'
        self.patch = legacy_ws.Patch(self.legacy_state, self.sni_state, self.alias_state, self.deployment_state)
        self.http_health = self.stack.enter_context(mock.patch.object(legacy_ws, 'http_site_healthy'))
        self.reload.reset_mock()
        self.run.reset_mock()

    def tearDown(self):
        sni_tests.DefaultSniTests.tearDown(self)

    def assert_protected(self):
        sni_tests.DefaultSniTests.assert_protected(self)
        for name, value in self.sni_bytes.items():
            self.assertEqual(value, (self.sni_state / name).read_bytes())

    def test_candidate_adds_only_one_exact_ip_site_preserving_all_old_bytes(self):
        after = legacy_ws.candidate(self.before_legacy)
        self.assertEqual(self.before_legacy, after[:len(self.before_legacy)])
        addition = after[len(self.before_legacy):].decode('ascii')
        self.assertEqual(1, addition.count('http://39.106.212.138 {'))
        self.assertIn('@belt_legacy_ws path /' + deploy.PLACEHOLDER_TOKEN + '/wsHat\n', addition)
        self.assertIn('reverse_proxy 10.255.1.1:28087', addition)
        self.assertIn('handle {\n        respond 404\n    }', addition)
        self.assertNotIn('*', addition)
        self.assertNotIn('handle_path', addition)
        self.assertNotIn('redir', addition)
        self.assertEqual(2, after.count(self.helmet_token.encode('ascii')))
        for invalid in [after, self.before_legacy[len(default_sni.PREFIX):],
                        self.before_legacy + b'http://39.106.212.138 {\n}\n',
                        self.before_legacy.replace(b'28087', b'28086'),
                        self.before_legacy.replace(b'/wsBelt\n', b'/wsBelt /*\n'),
                        self.before_legacy + route_alias.BEGIN]:
            with self.assertRaises(deploy.DeployError):
                legacy_ws.candidate(invalid)

    def test_success_repeat_and_rollback_preserve_all_old_journals_and_inode(self):
        self.patch.preview()
        preview = (self.legacy_state / 'patch-preview.json').read_bytes()
        self.patch.preview()
        self.assertEqual(preview, (self.legacy_state / 'patch-preview.json').read_bytes())
        self.assertEqual({'patch', 'sni', 'alias', 'helper'}, set(self.patch.load()['scripts']))
        self.patch.apply()
        self.assertEqual(legacy_ws.candidate(self.before_legacy), self.caddy.read_bytes())
        self.assertEqual(1, self.reload.call_count)
        self.http_health.assert_called_once_with()
        self.patch.apply()
        self.assertEqual(1, self.reload.call_count)
        self.assert_protected()
        self.patch.rollback()
        self.patch.rollback()
        self.assertEqual(self.before_legacy, self.caddy.read_bytes())
        self.assertEqual('rolled-back', deploy.load_json(self.patch.journal)['status'])
        self.assert_protected()
        for call in self.run.call_args_list:
            self.assertEqual(['docker', 'exec', '-i', deploy.CONTAINER, 'caddy', 'validate'], call[0][2][:6])

    def test_sni_must_be_applied_and_active_caddy_must_match_its_hash(self):
        journal = self.sni_state / 'patch-transaction.json'
        transaction = deploy.load_json(journal)
        deploy.save_json(journal, dict(transaction, status='rolled-back'))
        with self.assertRaises(deploy.DeployError):
            self.patch.preview()
        journal.write_bytes(self.sni_bytes['patch-transaction.json'])
        self.caddy.write_bytes(self.before_legacy + b'\n# later change\n')
        with self.assertRaises(deploy.DeployError):
            self.patch.preview()
        self.reload.assert_not_called()

    def test_changed_chain_or_protected_resource_after_preview_prevents_apply(self):
        self.patch.preview()
        for path in [self.sni_state / 'patch-transaction.json', self.alias_state / 'patch-transaction.json', self.deployment_state / 'deployment.json',
                     self.sshd, self.key_file]:
            saved = path.read_bytes()
            path.write_bytes(saved + b'\n')
            with self.assertRaises(deploy.DeployError):
                self.patch.apply()
            path.write_bytes(saved)
        self.assertEqual(self.before_legacy, self.caddy.read_bytes())
        self.reload.assert_not_called()
        self.assert_protected()

    def test_caddy_validation_failure_never_creates_transaction_or_changes_active_file(self):
        self.patch.preview()
        self.run.side_effect = deploy.DeployError('validation failed')
        with self.assertRaises(deploy.DeployError):
            self.patch.apply()
        self.assertFalse(self.patch.journal.exists())
        self.assertEqual(self.before_legacy, self.caddy.read_bytes())
        self.assert_protected()

    def test_reload_failure_and_final_journal_failure_restore_prior_configuration(self):
        self.patch.preview()
        self.reload.side_effect = [deploy.DeployError('reload failure'), None]
        with self.assertRaisesRegex(deploy.DeployError, 'restored and reloaded'):
            self.patch.apply()
        self.assertEqual(self.before_legacy, self.caddy.read_bytes())
        self.assert_protected()
        self.reload.side_effect = None
        second = legacy_ws.Patch(self.root / 'second-legacy-patch', self.sni_state, self.alias_state, self.deployment_state)
        second.preview()
        save = deploy.save_json
        def fail_applied(path, value):
            if path == second.journal and value.get('status') == 'applied':
                raise deploy.DeployError('journal failure')
            return save(path, value)
        with mock.patch.object(deploy, 'save_json', side_effect=fail_applied):
            with self.assertRaisesRegex(deploy.DeployError, 'restored and reloaded'):
                second.apply()
        self.assertEqual(self.before_legacy, self.caddy.read_bytes())
        self.assertEqual('rolled-back', deploy.load_json(second.journal)['status'])
        self.assert_protected()

    def test_recovery_reload_failure_is_retryable_and_later_external_change_is_preserved(self):
        self.patch.preview()
        self.reload.side_effect = deploy.DeployError('reload failure')
        with self.assertRaisesRegex(deploy.DeployError, 'restoration needs attention'):
            self.patch.apply()
        self.assertEqual(self.before_legacy, self.caddy.read_bytes())
        self.reload.side_effect = None
        self.patch.rollback()
        self.assertEqual('rolled-back', deploy.load_json(self.patch.journal)['status'])
        later = self.before_legacy + b'\n# another operator\n'
        self.caddy.write_bytes(later)
        with self.assertRaisesRegex(deploy.DeployError, 'later changes were not overwritten'):
            self.patch.rollback()
        self.assertEqual(later, self.caddy.read_bytes())
        self.assert_protected()

    def test_prepared_transaction_resumes_after_write_without_duplicating_site(self):
        self.patch.preview()
        plan = self.patch.load()
        deploy.save_json(self.patch.journal,
                         {'kind': legacy_ws.KIND, 'status': 'prepared', 'afterSha256': plan['afterSha256']})
        self.caddy.write_bytes((self.legacy_state / 'after.Caddyfile').read_bytes())
        self.patch.apply()
        self.assertEqual(legacy_ws.candidate(self.before_legacy), self.caddy.read_bytes())
        self.assertEqual('applied', deploy.load_json(self.patch.journal)['status'])
        self.assert_protected()

    def test_http_site_health_failure_restores_prior_https_configuration(self):
        self.patch.preview()
        self.http_health.side_effect = deploy.DeployError('isolated HTTP health failure')
        with self.assertRaisesRegex(deploy.DeployError, 'restored and reloaded'):
            self.patch.apply()
        self.assertEqual(self.before_legacy, self.caddy.read_bytes())
        self.assertEqual('rolled-back', deploy.load_json(self.patch.journal)['status'])
        self.assert_protected()

    def test_state_directories_are_separate_and_changed_scripts_prevent_apply(self):
        for state in [self.sni_state, self.alias_state, self.deployment_state,
                      self.sni_state / 'child', self.root]:
            with self.assertRaises(deploy.DeployError):
                legacy_ws.Patch(state, self.sni_state, self.alias_state, self.deployment_state)
        self.patch.preview()
        with mock.patch.object(legacy_ws, 'script_hashes', return_value={}):
            with self.assertRaisesRegex(deploy.DeployError, 'scripts changed'):
                self.patch.apply()
        self.reload.assert_not_called()
        self.assert_protected()


class HttpSiteHealthTests(unittest.TestCase):
    def test_only_unrelated_path_is_sent_with_ip_host_and_404_required(self):
        for status in [404, 200, 301, 502]:
            conn = mock.Mock()
            conn.getresponse.return_value.status = status
            with mock.patch.object(legacy_ws.http.client, 'HTTPConnection', return_value=conn) as factory:
                if status == 404:
                    legacy_ws.http_site_healthy()
                else:
                    with self.assertRaises(deploy.DeployError):
                        legacy_ws.http_site_healthy()
                factory.assert_called_once_with('127.0.0.1', 80, timeout=12)
                conn.request.assert_called_once_with('GET', '/belt-legacy-ws-probe-no-credential',
                    headers={'Host': deploy.TARGET_IP, 'Connection': 'close'})
                conn.close.assert_called_once_with()

    def test_network_failure_is_closed_and_does_not_expose_exception_text(self):
        conn = mock.Mock()
        conn.request.side_effect = OSError('sensitive diagnostic must not escape')
        with mock.patch.object(legacy_ws.http.client, 'HTTPConnection', return_value=conn):
            with self.assertRaises(deploy.DeployError) as caught:
                legacy_ws.http_site_healthy()
        self.assertNotIn('sensitive', str(caught.exception))
        conn.close.assert_called_once_with()


if __name__ == '__main__':
    unittest.main()
