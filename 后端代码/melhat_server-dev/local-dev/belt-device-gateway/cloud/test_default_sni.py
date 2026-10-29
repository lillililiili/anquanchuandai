import unittest
from unittest import mock

import deploy
import route_alias
import default_sni
import test_route_alias as alias_tests


class DefaultSniTests(unittest.TestCase):
    def setUp(self):
        alias_tests.RouteAliasTests.setUp(self)
        self.alias_state = self.patch_state
        route_alias.preview(self.alias_state, self.deployment_state)
        route_alias.apply(self.alias_state, self.deployment_state)
        self.alias_bytes = {name: (self.alias_state / name).read_bytes()
                            for name in ['patch-preview.json', 'patch-transaction.json']}
        self.before_sni = self.caddy.read_bytes()
        self.sni_state = self.root / 'default-sni-patch'
        self.patch = default_sni.Patch(self.sni_state, self.alias_state, self.deployment_state)
        self.reload.reset_mock()
        self.run.reset_mock()

    def tearDown(self):
        alias_tests.RouteAliasTests.tearDown(self)

    def assert_protected(self):
        alias_tests.RouteAliasTests.assert_protected(self)
        for name, value in self.alias_bytes.items():
            self.assertEqual(value, (self.alias_state / name).read_bytes())

    def test_candidate_is_only_fixed_prefix_and_refuses_existing_global_options(self):
        after = default_sni.candidate(self.before_sni)
        self.assertEqual(default_sni.PREFIX, after[:-len(self.before_sni)])
        self.assertEqual(self.before_sni, after[len(default_sni.PREFIX):])
        for invalid in [after, b'{\n    debug\n}\n' + self.before_sni,
                        b'other.example {\n}\n', self.before_sni + b'\ndefault_sni other.example\n']:
            with self.assertRaises(deploy.DeployError):
                default_sni.candidate(invalid)

    def test_success_repeat_and_rollback_preserve_both_old_journals_and_inode(self):
        self.patch.preview()
        preview = (self.sni_state / 'patch-preview.json').read_bytes()
        self.patch.preview()
        self.assertEqual(preview, (self.sni_state / 'patch-preview.json').read_bytes())
        self.patch.apply()
        self.assertEqual(default_sni.PREFIX + self.before_sni, self.caddy.read_bytes())
        self.assertEqual(1, self.reload.call_count)
        self.patch.apply()
        self.assertEqual(1, self.reload.call_count)
        self.assert_protected()
        self.patch.rollback()
        self.patch.rollback()
        self.assertEqual(self.before_sni, self.caddy.read_bytes())
        self.assertEqual('rolled-back', deploy.load_json(self.patch.journal)['status'])
        self.assert_protected()
        for call in self.run.call_args_list:
            self.assertEqual(['docker', 'exec', '-i', deploy.CONTAINER, 'caddy', 'validate'], call[0][2][:6])

    def test_alias_must_be_applied_and_active_caddy_must_match_its_hash(self):
        journal = self.alias_state / 'patch-transaction.json'
        transaction = deploy.load_json(journal)
        deploy.save_json(journal, dict(transaction, status='rolled-back'))
        with self.assertRaises(deploy.DeployError):
            self.patch.preview()
        journal.write_bytes(self.alias_bytes['patch-transaction.json'])
        self.caddy.write_bytes(self.before_sni + b'\n# later change\n')
        with self.assertRaises(deploy.DeployError):
            self.patch.preview()
        self.reload.assert_not_called()

    def test_changed_chain_or_protected_resource_after_preview_prevents_apply(self):
        self.patch.preview()
        for path in [self.alias_state / 'patch-transaction.json', self.deployment_state / 'deployment.json',
                     self.sshd, self.key_file]:
            saved = path.read_bytes()
            path.write_bytes(saved + b'\n')
            with self.assertRaises(deploy.DeployError):
                self.patch.apply()
            path.write_bytes(saved)
        self.assertEqual(self.before_sni, self.caddy.read_bytes())
        self.reload.assert_not_called()
        self.assert_protected()

    def test_caddy_validation_failure_never_creates_transaction_or_changes_active_file(self):
        self.patch.preview()
        self.run.side_effect = deploy.DeployError('validation failed')
        with self.assertRaises(deploy.DeployError):
            self.patch.apply()
        self.assertFalse(self.patch.journal.exists())
        self.assertEqual(self.before_sni, self.caddy.read_bytes())
        self.assert_protected()

    def test_reload_failure_and_final_journal_failure_restore_prior_configuration(self):
        self.patch.preview()
        self.reload.side_effect = [deploy.DeployError('reload failure'), None]
        with self.assertRaisesRegex(deploy.DeployError, 'restored and reloaded'):
            self.patch.apply()
        self.assertEqual(self.before_sni, self.caddy.read_bytes())
        self.assert_protected()
        self.reload.side_effect = None
        second = default_sni.Patch(self.root / 'second-sni-patch', self.alias_state, self.deployment_state)
        second.preview()
        save = deploy.save_json
        def fail_applied(path, value):
            if path == second.journal and value.get('status') == 'applied':
                raise deploy.DeployError('journal failure')
            return save(path, value)
        with mock.patch.object(deploy, 'save_json', side_effect=fail_applied):
            with self.assertRaisesRegex(deploy.DeployError, 'restored and reloaded'):
                second.apply()
        self.assertEqual(self.before_sni, self.caddy.read_bytes())
        self.assertEqual('rolled-back', deploy.load_json(second.journal)['status'])
        self.assert_protected()

    def test_recovery_reload_failure_is_retryable_and_later_external_change_is_preserved(self):
        self.patch.preview()
        self.reload.side_effect = deploy.DeployError('reload failure')
        with self.assertRaisesRegex(deploy.DeployError, 'restoration needs attention'):
            self.patch.apply()
        self.assertEqual(self.before_sni, self.caddy.read_bytes())
        self.reload.side_effect = None
        self.patch.rollback()
        self.assertEqual('rolled-back', deploy.load_json(self.patch.journal)['status'])
        later = self.before_sni + b'\n# another operator\n'
        self.caddy.write_bytes(later)
        with self.assertRaisesRegex(deploy.DeployError, 'later changes were not overwritten'):
            self.patch.rollback()
        self.assertEqual(later, self.caddy.read_bytes())
        self.assert_protected()

    def test_prepared_transaction_resumes_after_write_without_duplicating_options(self):
        self.patch.preview()
        plan = self.patch.load()
        deploy.save_json(self.patch.journal,
                         {'kind': default_sni.KIND, 'status': 'prepared', 'afterSha256': plan['afterSha256']})
        self.caddy.write_bytes((self.sni_state / 'after.Caddyfile').read_bytes())
        self.patch.apply()
        self.assertEqual(default_sni.PREFIX + self.before_sni, self.caddy.read_bytes())
        self.assertEqual('applied', deploy.load_json(self.patch.journal)['status'])
        self.assert_protected()


if __name__ == '__main__':
    unittest.main()
