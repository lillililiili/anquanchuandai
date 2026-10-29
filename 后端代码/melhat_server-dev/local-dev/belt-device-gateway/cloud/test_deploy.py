import base64
import contextlib
import io
import json
import os
import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import deploy


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.caddy = self.root / 'Caddyfile'
        self.sshd = self.root / 'sshd_config'
        self.tail = '\nwww.{$DOMAIN} {\n    handle /baidu_verify_unchanged.txt {\n        respond "original"\n    }\n    redir https://{$DOMAIN}{uri}\n}\n'
        self.helmet_token = base64.urlsafe_b64encode(b'H' * 32).decode('ascii').rstrip('=')
        self.helmet_block = '''{$DOMAIN} {
    encode zstd gzip
    # BEGIN HELMET DEVICE GATEWAY
    @helmet_device path /%s/api/index.php /%s/wsHat
    handle @helmet_device {
        reverse_proxy 10.255.1.1:28086
    }
    # END HELMET DEVICE GATEWAY
    handle {
        reverse_proxy nginx:80
    }
}
''' % (self.helmet_token, self.helmet_token)
        self.caddy_original = (self.helmet_block + self.tail).encode('utf-8')
        self.ssh_original = (b'Port 22\nGatewayPorts no\nAllowTcpForwarding yes\nUsePAM yes\n'
                             b'# BEGIN HELMET DEVICE GATEWAY\nMatch User helmet-tunnel\n'
                             b'    PermitListen 10.255.1.1:28086\n# END HELMET DEVICE GATEWAY\n\n')
        self.caddy.write_bytes(self.caddy_original)
        self.sshd.write_bytes(self.ssh_original)
        algorithm = b'ssh-ed25519'
        self.key = 'ssh-ed25519 ' + base64.b64encode(struct.pack('>I', len(algorithm)) + algorithm + struct.pack('>I', 32) + b'K' * 32).decode('ascii')
        self.state = self.root / 'state'
        self.state.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def make_plan(self):
        caddy, caddy_meta = deploy.snapshot(self.caddy)
        sshd, ssh_meta = deploy.snapshot(self.sshd)
        (self.state / 'original.Caddyfile').write_bytes(caddy)
        (self.state / 'original.sshd_config').write_bytes(sshd)
        plan = {'version': 1, 'deploymentKind': 'belt-device-gateway',
                'dedicatedUser': deploy.USER, 'listenPort': deploy.PORT,
                'targetIp': deploy.TARGET_IP, 'domain': deploy.DOMAIN,
                'service': 'sshd.service', 'scriptSha256': deploy.digest(Path(deploy.__file__).read_bytes()),
                'original': {'caddy': caddy_meta, 'sshd': ssh_meta}}
        deploy.save_json(self.state / 'preview.json', plan)
        return plan

    def test_real_private_inputs_and_placeholder_are_valid(self):
        self.assertEqual(43, len(deploy.validate_token(deploy.PLACEHOLDER_TOKEN)))
        self.assertEqual(self.key, deploy.validate_public_key(self.key + ' local-comment\n'))
        for key in ['ssh-rsa AAAA', self.key + '\ncommand="bad"', 'ssh-ed25519 AAAA']:
            with self.assertRaises(deploy.DeployError):
                deploy.validate_public_key(key)

    def test_exact_paths_preserve_uri_and_remaining_site_bytes(self):
        caddy, ssh = deploy.candidates(self.caddy_original, self.ssh_original, deploy.PLACEHOLDER_TOKEN)
        self.assertTrue(caddy.endswith(self.tail.encode('utf-8')))
        self.assertEqual(3, caddy.count(deploy.PLACEHOLDER_TOKEN.encode('ascii')))
        self.assertIn(b'@belt_device path /', caddy)
        self.assertIn(('/' + deploy.PLACEHOLDER_TOKEN + '/api/belt/index.php').encode('ascii'), caddy)
        self.assertIn(('/' + deploy.PLACEHOLDER_TOKEN + '/api/belt/config/index.php').encode('ascii'), caddy)
        route_line = next(line for line in caddy.decode('utf-8').splitlines() if '@belt_device path ' in line)
        self.assertEqual(['/' + deploy.PLACEHOLDER_TOKEN + suffix for suffix in
                          ['/api/belt/index.php', '/api/belt/config/index.php', '/wsBelt']], route_line.split()[2:])
        start = caddy.index(b'    # BEGIN BELT DEVICE GATEWAY\n')
        end = caddy.index(b'    # END BELT DEVICE GATEWAY\n') + len(b'    # END BELT DEVICE GATEWAY\n')
        self.assertEqual(self.caddy_original, caddy[:start] + caddy[end:])
        self.assertEqual(2, caddy.count(self.helmet_token.encode('ascii')))
        self.assertIn(b'reverse_proxy 10.255.1.1:28086', caddy)
        self.assertIn(b'    handle {\n        reverse_proxy nginx:80\n', caddy)
        self.assertNotIn(b'handle_path', caddy)
        self.assertNotIn(b'uri strip_prefix', caddy)
        self.assertTrue(ssh.startswith(self.ssh_original))
        self.assertEqual(1, ssh.count(b'Match User helmet-tunnel'))
        for key, value in deploy.EXPECTED_SSH.items():
            self.assertIn((key + ' ' + value).encode('ascii'), ssh.lower())

    def test_changed_site_or_previous_managed_block_is_rejected(self):
        for caddy, ssh in [(self.caddy_original.replace(b'nginx:80', b'other:80'), self.ssh_original),
                           (self.caddy_original, self.ssh_original + b'# BELT DEVICE GATEWAY')]:
            with self.assertRaises(deploy.DeployError):
                deploy.candidates(caddy, ssh, deploy.PLACEHOLDER_TOKEN)

    def test_in_place_write_keeps_inode_and_rejects_changed_hash(self):
        original_inode = self.caddy.stat().st_ino
        deploy.write_in_place(self.caddy, deploy.digest(self.caddy_original), b'new contents\n')
        self.assertEqual(original_inode, self.caddy.stat().st_ino)
        with self.assertRaises(deploy.DeployError):
            deploy.write_in_place(self.caddy, deploy.digest(self.caddy_original), b'overwrite')
        self.assertEqual(b'new contents\n', self.caddy.read_bytes())

    def test_atomic_json_write_failure_preserves_previous_transaction(self):
        path = self.state / 'deployment.json'
        previous = {'status': 'account-created', 'accountUid': 12345}
        deploy.save_json(path, previous)
        before = path.read_bytes()
        with mock.patch.object(deploy.os, 'fsync', side_effect=OSError('disk full')):
            with self.assertRaises(deploy.DeployError):
                deploy.save_json(path, {'status': 'applied', 'accountUid': 12345})
        self.assertEqual(before, path.read_bytes())
        self.assertEqual(previous, deploy.load_json(path))
        self.assertEqual(['deployment.json'], sorted(item.name for item in self.state.iterdir()))

    def test_atomic_json_replace_failure_preserves_previous_transaction(self):
        path = self.state / 'deployment.json'
        previous = {'status': 'account-created', 'accountUid': 12345}
        deploy.save_json(path, previous)
        with mock.patch.object(deploy.os, 'replace', side_effect=OSError('replace denied')):
            with self.assertRaises(deploy.DeployError):
                deploy.save_json(path, {'status': 'applied', 'accountUid': 12345})
        self.assertEqual(previous, deploy.load_json(path))
        self.assertEqual(['deployment.json'], sorted(item.name for item in self.state.iterdir()))
        deploy.save_json(path, {'status': 'applied', 'accountUid': 12345})
        self.assertEqual('applied', deploy.load_json(path)['status'])

    def test_failed_final_transaction_save_still_rolls_back_active_configuration(self):
        self.make_plan()
        private_settings = self.root / 'private.json'
        deploy.save_json(private_settings, {'pathToken': deploy.PLACEHOLDER_TOKEN, 'publicKey': self.key})
        home = self.root / 'belt-home'
        account = mock.Mock(pw_uid=12345, pw_gid=12345, pw_dir=str(home))
        user_database = mock.Mock()
        user_database.getpwnam.return_value = account
        group_database = mock.Mock()
        group_database.getgrnam.side_effect = KeyError(deploy.USER)
        replace = deploy.os.replace
        def fail_applied_commit(source, target):
            if Path(target).name == 'deployment.json' and deploy.load_json(Path(source)).get('status') == 'applied':
                raise OSError('final journal commit failed')
            return replace(source, target)
        with mock.patch.multiple(deploy, CADDY=self.caddy, SSHD=self.sshd, HOME=home,
                                 pwd=user_database, grp=group_database), \
             mock.patch.object(deploy, 'require_absent_user'), \
             mock.patch.object(deploy, 'port_available'), \
             mock.patch.object(deploy, 'server_ready', return_value='sshd.service'), \
             mock.patch.object(deploy, 'validate_candidates'), \
             mock.patch.object(deploy, 'website_healthy'), \
             mock.patch.object(deploy.os, 'chown', create=True), \
             mock.patch.object(deploy.os, 'replace', side_effect=fail_applied_commit), \
             mock.patch.object(deploy, 'reload_caddy') as reload_caddy, \
             mock.patch.object(deploy, 'run', return_value=mock.Mock(returncode=0)) as run, \
             contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(deploy.DeployError, 'was rolled back'):
                deploy.apply(self.state, private_settings)
        self.assertEqual(self.caddy_original, self.caddy.read_bytes())
        self.assertEqual(self.ssh_original, self.sshd.read_bytes())
        self.assertEqual('rolled-back', deploy.load_json(self.state / 'deployment.json')['status'])
        self.assertEqual(2, reload_caddy.call_count)
        self.assertFalse(home.exists())
        self.assertIn(['userdel', deploy.USER], [call[0][2] for call in run.call_args_list])

    def test_partial_write_failure_restores_original_on_same_inode(self):
        original_inode = self.caddy.stat().st_ino
        with mock.patch.object(deploy.os, 'fsync', side_effect=[OSError('disk error'), None]):
            with self.assertRaises(deploy.DeployError):
                deploy.write_in_place(self.caddy, deploy.digest(self.caddy_original), b'incomplete')
        self.assertEqual(self.caddy_original, self.caddy.read_bytes())
        self.assertEqual(original_inode, self.caddy.stat().st_ino)

    def test_equal_contents_inode_replacement_is_rejected(self):
        original_inode = self.caddy.stat().st_ino
        replacement = self.root / 'replacement'
        replacement.write_bytes(self.caddy_original)
        os.replace(str(replacement), str(self.caddy))
        with self.assertRaises(deploy.DeployError):
            deploy.write_in_place(self.caddy, deploy.digest(self.caddy_original), b'changed', original_inode)
        self.assertEqual(self.caddy_original, self.caddy.read_bytes())

    def test_preview_does_not_mutate_active_configs_or_create_account(self):
        output = io.StringIO()
        with mock.patch.multiple(deploy, CADDY=self.caddy, SSHD=self.sshd), \
             mock.patch.object(deploy, 'require_absent_user'), \
             mock.patch.object(deploy, 'port_available'), \
             mock.patch.object(deploy, 'server_ready', return_value='sshd.service'), \
             mock.patch.object(deploy, 'validate_candidates') as validate, \
             mock.patch.object(deploy, 'run') as run, contextlib.redirect_stdout(output):
            deploy.preview(self.state)
        self.assertEqual(self.caddy_original, self.caddy.read_bytes())
        self.assertEqual(self.ssh_original, self.sshd.read_bytes())
        validate.assert_called_once()
        run.assert_not_called()
        self.assertNotIn(deploy.PLACEHOLDER_TOKEN, output.getvalue())

    def test_baseline_detects_active_changes_and_backup_tampering(self):
        plan = self.make_plan()
        with mock.patch.multiple(deploy, CADDY=self.caddy, SSHD=self.sshd):
            deploy.check_baseline(plan, self.state)
            self.caddy.write_bytes(self.caddy_original + b'# later edit')
            with self.assertRaises(deploy.DeployError):
                deploy.check_baseline(plan, self.state)
            self.caddy.write_bytes(self.caddy_original)
            (self.state / 'original.Caddyfile').write_bytes(b'tampered')
            with self.assertRaises(deploy.DeployError):
                deploy.check_baseline(plan, self.state)

    def test_command_output_is_private_and_does_not_use_new_python_apis(self):
        result = mock.Mock(returncode=1, stdout=('/' + deploy.PLACEHOLDER_TOKEN + '/wsBelt').encode('ascii'), stderr=b'diagnostic')
        output = io.StringIO()
        with mock.patch.object(deploy.subprocess, 'run', return_value=result) as run, contextlib.redirect_stdout(output):
            with self.assertRaises(deploy.DeployError) as error:
                deploy.run(self.state, 'validation', ['dummy'])
        self.assertNotIn('secret', str(error.exception))
        self.assertEqual('', output.getvalue())
        self.assertEqual(b'/[REDACTED-PATH-CREDENTIAL]/wsBelt\ndiagnostic', (self.state / 'validation.log').read_bytes())
        self.assertNotIn('text', run.call_args[1])
        self.assertNotIn('capture_output', run.call_args[1])

    def test_rollback_restores_both_files_in_place_and_only_reloads(self):
        plan = self.make_plan()
        caddy, ssh = deploy.candidates(self.caddy_original, self.ssh_original, deploy.PLACEHOLDER_TOKEN)
        self.caddy.write_bytes(caddy)
        self.sshd.write_bytes(ssh)
        deploy.save_json(self.state / 'deployment.json', {'accountUid': None, 'service': 'sshd.service',
            'deployed': {'caddy': deploy.digest(caddy), 'sshd': deploy.digest(ssh)}})
        with mock.patch.multiple(deploy, CADDY=self.caddy, SSHD=self.sshd), \
             mock.patch.object(deploy, 'reload_caddy') as reload_caddy, \
             mock.patch.object(deploy, 'require_absent_user'), \
             mock.patch.object(deploy, 'run') as run, contextlib.redirect_stdout(io.StringIO()):
            deploy.rollback(self.state)
        self.assertEqual(self.caddy_original, self.caddy.read_bytes())
        self.assertEqual(self.ssh_original, self.sshd.read_bytes())
        self.assertEqual(plan['original']['caddy']['inode'], self.caddy.stat().st_ino)
        reload_caddy.assert_called_once()
        self.assertIn(['systemctl', 'reload', 'sshd.service'], [call[0][2] for call in run.call_args_list])
        self.assertFalse(any('restart' in call[0][2] for call in run.call_args_list))

    def test_rollback_preserves_subsequent_external_change(self):
        self.make_plan()
        caddy, ssh = deploy.candidates(self.caddy_original, self.ssh_original, deploy.PLACEHOLDER_TOKEN)
        self.caddy.write_bytes(caddy + b'# another operator edit\n')
        self.sshd.write_bytes(ssh)
        deploy.save_json(self.state / 'deployment.json', {'accountUid': None, 'service': 'sshd.service',
            'deployed': {'caddy': deploy.digest(caddy), 'sshd': deploy.digest(ssh)}})
        with mock.patch.multiple(deploy, CADDY=self.caddy, SSHD=self.sshd), \
             mock.patch.object(deploy, 'require_absent_user'), \
             mock.patch.object(deploy, 'reload_caddy'), mock.patch.object(deploy, 'run'):
            with self.assertRaises(deploy.DeployError):
                deploy.rollback(self.state)
        self.assertTrue(self.caddy.read_bytes().endswith(b'# another operator edit\n'))
        self.assertEqual(self.ssh_original, self.sshd.read_bytes())
        self.assertEqual('rollback-needs-attention', deploy.load_json(self.state / 'deployment.json')['status'])

    def test_repeated_rollback_retries_failed_reload_even_after_bytes_restored(self):
        self.make_plan()
        caddy, ssh = deploy.candidates(self.caddy_original, self.ssh_original, deploy.PLACEHOLDER_TOKEN)
        self.caddy.write_bytes(caddy)
        self.sshd.write_bytes(ssh)
        deploy.save_json(self.state / 'deployment.json', {'accountUid': None, 'service': 'sshd.service',
            'deployed': {'caddy': deploy.digest(caddy), 'sshd': deploy.digest(ssh)}})
        with mock.patch.multiple(deploy, CADDY=self.caddy, SSHD=self.sshd), \
             mock.patch.object(deploy, 'require_absent_user'), \
             mock.patch.object(deploy, 'run'), \
             mock.patch.object(deploy, 'reload_caddy', side_effect=[deploy.DeployError('reload failed'), None]) as reload_caddy, \
             contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(deploy.DeployError):
                deploy.rollback(self.state)
            self.assertEqual(self.caddy_original, self.caddy.read_bytes())
            deploy.rollback(self.state)
        self.assertEqual(2, reload_caddy.call_count)
        self.assertEqual('rolled-back', deploy.load_json(self.state / 'deployment.json')['status'])

    def test_unrecorded_partial_useradd_never_reports_rollback_success(self):
        self.make_plan()
        deploy.save_json(self.state / 'deployment.json', {'accountUid': None, 'service': 'sshd.service',
            'deployed': {'caddy': 'unused', 'sshd': 'unused'}})
        with mock.patch.multiple(deploy, CADDY=self.caddy, SSHD=self.sshd), \
             mock.patch.object(deploy, 'require_absent_user', side_effect=deploy.DeployError('user appeared')), \
             mock.patch.object(deploy, 'reload_caddy'), mock.patch.object(deploy, 'run') as run:
            with self.assertRaises(deploy.DeployError):
                deploy.rollback(self.state)
        self.assertEqual('rollback-needs-attention', deploy.load_json(self.state / 'deployment.json')['status'])
        self.assertFalse(any('userdel' in call[0][2] for call in run.call_args_list))

    def test_stale_single_file_mount_inode_is_rejected(self):
        def fake_run(state, label, args, **kwargs):
            if label == 'container-running':
                return mock.Mock(stdout=b'true', returncode=0)
            if label == 'container-mounts':
                return mock.Mock(stdout=json.dumps([{'Type': 'bind', 'Source': str(self.caddy),
                    'Destination': '/etc/caddy/Caddyfile'}]).encode('utf-8'), returncode=0)
            if label == 'container-config-inode':
                return mock.Mock(stdout=b'0', returncode=0)
            raise AssertionError('Unexpected command')
        with mock.patch.object(deploy, 'CADDY', self.caddy), \
             mock.patch.object(deploy, 'run', side_effect=fake_run), \
             mock.patch.object(deploy, 'website_healthy') as healthy:
            with self.assertRaises(deploy.DeployError):
                deploy.server_ready(self.state)
        healthy.assert_not_called()

    def test_backup_archive_refuses_overwrite(self):
        self.make_plan()
        deploy.archive_originals(self.state)
        with self.assertRaises(deploy.DeployError):
            deploy.archive_originals(self.state)

    def test_helmet_credential_cannot_be_reused_for_belt(self):
        with self.assertRaises(deploy.DeployError):
            deploy.candidates(self.caddy_original, self.ssh_original, self.helmet_token)

    def test_rollback_rejects_helmet_state_before_any_mutation(self):
        plan = self.make_plan()
        plan.pop('deploymentKind')
        deploy.save_json(self.state / 'preview.json', plan)
        with mock.patch.multiple(deploy, CADDY=self.caddy, SSHD=self.sshd), \
             mock.patch.object(deploy, 'run') as run, \
             mock.patch.object(deploy, 'require_absent_user') as absent:
            with self.assertRaises(deploy.DeployError):
                deploy.rollback(self.state)
        self.assertEqual(self.caddy_original, self.caddy.read_bytes())
        self.assertEqual(self.ssh_original, self.sshd.read_bytes())
        run.assert_not_called()
        absent.assert_not_called()

    def test_existing_helmet_effective_ssh_policy_is_compared(self):
        effective = '\n'.join(key + ' ' + value for key, value in deploy.EXPECTED_SSH.items()) + '\nusepam yes\n'
        def policy(state, label, path, user):
            if user == deploy.USER:
                return effective.encode('ascii')
            if user == 'helmet-tunnel' and 'after-' in label:
                return b'changed helmet restriction'
            return b'original policy'
        with mock.patch.object(deploy, 'run'), \
             mock.patch.object(deploy, 'effective_ssh', side_effect=policy):
            with self.assertRaises(deploy.DeployError):
                deploy.validate_candidates(self.state, b'candidate', self.ssh_original, 'test')

    def test_effective_belt_ssh_policy_requires_dead_client_detection(self):
        for patch in ({'clientaliveinterval': '0'}, {'clientalivecountmax': '0'},
                      {'clientaliveinterval': '60'}, {'clientalivecountmax': '6'}):
            with self.subTest(patch=patch):
                actual = dict(deploy.EXPECTED_SSH, usepam='yes', **patch)
                effective = ('\n'.join(key + ' ' + value for key, value in actual.items()) + '\n').encode('ascii')
                with mock.patch.object(deploy, 'run'), \
                     mock.patch.object(deploy, 'effective_ssh', return_value=effective):
                    with self.assertRaisesRegex(deploy.DeployError, 'restrictions differ'):
                        deploy.validate_candidates(self.state, b'candidate', self.ssh_original, 'test')
        correct = dict(deploy.EXPECTED_SSH, usepam='yes')
        effective = ('\n'.join(key + ' ' + value for key, value in correct.items()) + '\n').encode('ascii')
        with mock.patch.object(deploy, 'run'), \
             mock.patch.object(deploy, 'effective_ssh', return_value=effective):
            deploy.validate_candidates(self.state, b'candidate', self.ssh_original, 'test')

    def test_successful_apply_and_duplicate_apply_are_isolated_from_helmet(self):
        self.make_plan()
        private_settings = self.root / 'private.json'
        deploy.save_json(private_settings, {'pathToken': deploy.PLACEHOLDER_TOKEN, 'publicKey': self.key})
        home = self.root / 'belt-home'
        account = mock.Mock(pw_uid=12345, pw_gid=12345, pw_dir=str(home))
        user_database = mock.Mock()
        user_database.getpwnam.return_value = account
        output = io.StringIO()
        with mock.patch.multiple(deploy, CADDY=self.caddy, SSHD=self.sshd, HOME=home, pwd=user_database), \
             mock.patch.object(deploy, 'require_absent_user'), \
             mock.patch.object(deploy, 'port_available'), \
             mock.patch.object(deploy, 'server_ready', return_value='sshd.service'), \
             mock.patch.object(deploy, 'validate_candidates'), \
             mock.patch.object(deploy, 'website_healthy'), \
             mock.patch.object(deploy.os, 'chown', create=True), \
             mock.patch.object(deploy, 'reload_caddy') as caddy_reload, \
             mock.patch.object(deploy, 'run') as run, contextlib.redirect_stdout(output):
            deploy.apply(self.state, private_settings)
            calls_after_apply = run.call_count
            with self.assertRaises(deploy.DeployError):
                deploy.apply(self.state, private_settings)
            self.assertEqual(calls_after_apply, run.call_count)
        self.assertEqual('applied', deploy.load_json(self.state / 'deployment.json')['status'])
        caddy_reload.assert_called_once()
        self.assertTrue(self.sshd.read_bytes().startswith(self.ssh_original))
        self.assertIn(self.helmet_token.encode('ascii'), self.caddy.read_bytes())
        self.assertIn(b'permitlisten="10.255.1.1:28087"', (home / '.ssh' / 'authorized_keys').read_bytes())
        commands = [call[0][2] for call in run.call_args_list]
        self.assertTrue(any(command[0] == 'useradd' and command[-1] == 'belt-tunnel' for command in commands))
        self.assertFalse(any('restart' in command or 'helmet-tunnel' in command for command in commands))
        self.assertNotIn(deploy.PLACEHOLDER_TOKEN, output.getvalue())

    def test_preview_and_duplicate_preview_never_overwrite_state(self):
        self.make_plan()
        original_plan = (self.state / 'preview.json').read_bytes()
        with self.assertRaises(deploy.DeployError):
            deploy.preview(self.state)
        self.assertEqual(original_plan, (self.state / 'preview.json').read_bytes())


if __name__ == '__main__':
    unittest.main()
