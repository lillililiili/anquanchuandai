import contextlib
import io
import types
import unittest
from unittest import mock

import deploy
import route_alias
import test_deploy as deployment_tests


class RouteAliasTests(unittest.TestCase):
    def setUp(self):
        deployment_tests.DeploymentTests.setUp(self)
        self.deployment_state = self.state
        self.patch_state = self.root / 'alias-patch'
        self.plan = deployment_tests.DeploymentTests.make_plan(self)
        current, ssh = deploy.candidates(self.caddy_original, self.ssh_original, deploy.PLACEHOLDER_TOKEN)
        self.alias = ('/' + deploy.PLACEHOLDER_TOKEN + '/api/belt/config/index.php ').encode('ascii')
        self.deployed_caddy = current.replace(self.alias, b'', 1)
        self.caddy.write_bytes(self.deployed_caddy)
        self.sshd.write_bytes(ssh)
        self.belt_home = self.root / 'belt-home'
        (self.belt_home / '.ssh').mkdir(parents=True)
        self.key_file = self.belt_home / '.ssh' / 'authorized_keys'
        self.key_file.write_bytes(b'isolated-public-key-fixture\n')
        self.transaction = {'status': 'applied', 'service': 'sshd.service', 'accountUid': 123, 'accountGid': 456,
                            'keySha256': deploy.digest(self.key_file.read_bytes()),
                            'deployed': {'caddy': deploy.digest(self.deployed_caddy), 'sshd': deploy.digest(ssh)}}
        deploy.save_json(self.deployment_state / 'deployment.json', self.transaction)
        self.original_journals = {name: (self.deployment_state / name).read_bytes()
                                  for name in ['preview.json', 'deployment.json']}
        self.protected_bytes = (self.sshd.read_bytes(), self.key_file.read_bytes())
        self.inode = self.caddy.stat().st_ino
        self.stack = contextlib.ExitStack()
        self.stack.enter_context(mock.patch.object(deploy, 'CADDY', self.caddy))
        self.stack.enter_context(mock.patch.object(deploy, 'SSHD', self.sshd))
        self.stack.enter_context(mock.patch.object(deploy, 'HOME', self.belt_home))
        account = types.SimpleNamespace(pw_uid=123, pw_gid=456, pw_dir=str(self.belt_home))
        self.stack.enter_context(mock.patch.object(deploy, 'pwd', types.SimpleNamespace(getpwnam=lambda name: account)))
        self.ready = self.stack.enter_context(mock.patch.object(deploy, 'server_ready', return_value='sshd.service'))
        self.run = self.stack.enter_context(mock.patch.object(deploy, 'run'))
        self.reload = self.stack.enter_context(mock.patch.object(deploy, 'reload_caddy'))
        self.health = self.stack.enter_context(mock.patch.object(deploy, 'website_healthy'))
        self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))

    def tearDown(self):
        self.stack.close()
        deployment_tests.DeploymentTests.tearDown(self)

    def preview(self):
        route_alias.preview(self.patch_state, self.deployment_state)

    def apply(self):
        route_alias.apply(self.patch_state, self.deployment_state)

    def rollback(self):
        route_alias.rollback(self.patch_state, self.deployment_state)

    def assert_protected(self):
        for name, original in self.original_journals.items():
            self.assertEqual(original, (self.deployment_state / name).read_bytes())
        self.assertEqual(self.protected_bytes, (self.sshd.read_bytes(), self.key_file.read_bytes()))
        self.assertEqual(self.inode, self.caddy.stat().st_ino)

    def test_candidate_adds_one_exact_path_without_touching_other_bytes(self):
        candidate = route_alias.route_candidate(self.deployed_caddy)
        self.assertEqual(self.deployed_caddy, candidate.replace(self.alias, b'', 1))
        self.assertEqual(1, candidate.count(self.alias))
        self.assertEqual(candidate, route_alias.route_candidate(candidate))
        self.assertEqual(2, candidate.count(self.helmet_token.encode('ascii')))
        self.assertTrue(candidate.endswith(self.tail.encode('utf-8')))

    def test_changed_duplicate_or_broad_routes_are_rejected(self):
        for data in [self.deployed_caddy + route_alias.BEGIN,
                     self.deployed_caddy.replace(b'28087', b'28086'),
                     self.deployed_caddy.replace(b'/wsBelt\n', b'/wsBelt /*\n'),
                     self.deployed_caddy.replace(b'/wsBelt\n', b'/wsOther\n'),
                     self.deployed_caddy.replace(route_alias.END, b'')]:
            with self.assertRaises(deploy.DeployError):
                route_alias.route_candidate(data)

    def test_preview_apply_and_rollback_are_repeatable_and_preserve_original_transaction(self):
        self.preview()
        before_preview = (self.patch_state / 'patch-preview.json').read_bytes()
        self.preview()
        self.assertEqual(before_preview, (self.patch_state / 'patch-preview.json').read_bytes())
        self.apply()
        self.assertEqual(route_alias.route_candidate(self.deployed_caddy), self.caddy.read_bytes())
        reloads = self.reload.call_count
        self.apply()
        self.assertEqual(reloads, self.reload.call_count)
        self.assert_protected()
        self.rollback()
        self.rollback()
        self.assertEqual(self.deployed_caddy, self.caddy.read_bytes())
        self.assertEqual('rolled-back', deploy.load_json(self.patch_state / 'patch-transaction.json')['status'])
        self.assert_protected()
        for call in self.run.call_args_list:
            self.assertEqual(['docker', 'exec', '-i', deploy.CONTAINER, 'caddy', 'validate'], call[0][2][:6])

    def test_preview_never_reuses_parent_or_nested_transaction_directories(self):
        for state in [self.deployment_state, self.deployment_state / 'child', self.root]:
            with self.assertRaises(deploy.DeployError):
                route_alias.preview(state, self.deployment_state)
        self.assert_protected()

    def test_invalid_candidate_or_changed_caddy_before_apply_never_writes(self):
        self.preview()
        self.run.side_effect = deploy.DeployError('validation failed')
        with self.assertRaises(deploy.DeployError):
            self.apply()
        self.assertEqual(self.deployed_caddy, self.caddy.read_bytes())
        self.assertFalse((self.patch_state / 'patch-transaction.json').exists())
        self.run.side_effect = None
        later = self.deployed_caddy + b'\n# subsequent external change\n'
        self.caddy.write_bytes(later)
        with self.assertRaises(deploy.DeployError):
            self.apply()
        self.assertEqual(later, self.caddy.read_bytes())
        self.reload.assert_not_called()

    def test_changed_ssh_key_or_parent_journal_stops_apply(self):
        self.preview()
        for path in [self.sshd, self.key_file, self.deployment_state / 'deployment.json']:
            saved = path.read_bytes()
            path.write_bytes(saved + b'\n')
            with self.assertRaises(deploy.DeployError):
                self.apply()
            path.write_bytes(saved)
        self.assertEqual(self.deployed_caddy, self.caddy.read_bytes())
        self.reload.assert_not_called()
        self.assert_protected()

    def test_unrelated_or_unapplied_deployment_is_not_accepted(self):
        transaction_file = self.deployment_state / 'deployment.json'
        deploy.save_json(transaction_file, dict(self.transaction, status='rolled-back'))
        with self.assertRaises(deploy.DeployError):
            self.preview()
        deploy.save_json(transaction_file, self.transaction)
        deploy.save_json(self.deployment_state / 'preview.json', dict(self.plan, deploymentKind='helmet-device-gateway'))
        with self.assertRaises(deploy.DeployError):
            self.preview()
        self.reload.assert_not_called()

    def test_apply_reload_failure_restores_original_inode_and_bytes(self):
        self.preview()
        self.reload.side_effect = [deploy.DeployError('reload failed'), None]
        with self.assertRaisesRegex(deploy.DeployError, 'restored and reloaded'):
            self.apply()
        self.assertEqual(self.deployed_caddy, self.caddy.read_bytes())
        self.assertEqual('rolled-back', deploy.load_json(self.patch_state / 'patch-transaction.json')['status'])
        self.assert_protected()

    def test_failed_final_journal_commit_also_restores_active_configuration(self):
        self.preview()
        save = deploy.save_json
        def fail_applied(path, value):
            if path.name == 'patch-transaction.json' and value.get('status') == 'applied':
                raise deploy.DeployError('journal failure')
            return save(path, value)
        with mock.patch.object(deploy, 'save_json', side_effect=fail_applied):
            with self.assertRaisesRegex(deploy.DeployError, 'restored and reloaded'):
                self.apply()
        self.assertEqual(self.deployed_caddy, self.caddy.read_bytes())
        self.assertEqual('rolled-back', deploy.load_json(self.patch_state / 'patch-transaction.json')['status'])
        self.assert_protected()

    def test_failed_recovery_reload_can_be_retried_without_rewriting_protected_resources(self):
        self.preview()
        self.reload.side_effect = deploy.DeployError('reload failed')
        with self.assertRaisesRegex(deploy.DeployError, 'restoration needs attention'):
            self.apply()
        self.assertEqual(self.deployed_caddy, self.caddy.read_bytes())
        self.assertEqual('rollback-needs-attention', deploy.load_json(self.patch_state / 'patch-transaction.json')['status'])
        self.reload.side_effect = None
        self.rollback()
        self.assertEqual('rolled-back', deploy.load_json(self.patch_state / 'patch-transaction.json')['status'])
        self.assert_protected()

    def test_prepared_journal_can_resume_after_process_exit_following_caddy_write(self):
        self.preview()
        plan = deploy.load_json(self.patch_state / 'patch-preview.json')
        deploy.save_json(self.patch_state / 'patch-transaction.json',
                         {'kind': route_alias.KIND, 'status': 'prepared', 'afterSha256': plan['afterSha256']})
        self.caddy.write_bytes((self.patch_state / 'after.Caddyfile').read_bytes())
        self.apply()
        self.assertEqual('applied', deploy.load_json(self.patch_state / 'patch-transaction.json')['status'])
        self.reload.assert_called_once()
        self.assert_protected()

    def test_later_caddy_change_is_never_overwritten_by_rollback(self):
        self.preview()
        self.apply()
        later = self.caddy.read_bytes() + b'\n# another operator\n'
        self.caddy.write_bytes(later)
        with self.assertRaisesRegex(deploy.DeployError, 'later changes were not overwritten'):
            self.rollback()
        self.assertEqual(later, self.caddy.read_bytes())
        self.assert_protected()


if __name__ == '__main__':
    unittest.main()
