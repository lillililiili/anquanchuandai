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
        self.caddy_original = (deploy.ORIGINAL_BLOCK + self.tail).encode('utf-8')
        self.ssh_original = b'Port 22\nGatewayPorts no\nAllowTcpForwarding yes\nUsePAM yes\n'
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
        plan = {'version': 1, 'targetIp': deploy.TARGET_IP, 'domain': deploy.DOMAIN,
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
        self.assertEqual(2, caddy.count(deploy.PLACEHOLDER_TOKEN.encode('ascii')))
        self.assertIn(b'@helmet_device path /', caddy)
        self.assertIn(b'    handle {\n        reverse_proxy nginx:80\n', caddy)
        self.assertNotIn(b'handle_path', caddy)
        self.assertNotIn(b'uri strip_prefix', caddy)
        self.assertTrue(ssh.startswith(self.ssh_original))
        for key, value in deploy.EXPECTED_SSH.items():
            self.assertIn((key + ' ' + value).encode('ascii'), ssh.lower())

    def test_changed_site_or_previous_managed_block_is_rejected(self):
        for caddy, ssh in [(self.caddy_original.replace(b'nginx:80', b'other:80'), self.ssh_original),
                           (self.caddy_original, self.ssh_original + b'# HELMET DEVICE GATEWAY')]:
            with self.assertRaises(deploy.DeployError):
                deploy.candidates(caddy, ssh, deploy.PLACEHOLDER_TOKEN)

    def test_in_place_write_keeps_inode_and_rejects_changed_hash(self):
        original_inode = self.caddy.stat().st_ino
        deploy.write_in_place(self.caddy, deploy.digest(self.caddy_original), b'new contents\n')
        self.assertEqual(original_inode, self.caddy.stat().st_ino)
        with self.assertRaises(deploy.DeployError):
            deploy.write_in_place(self.caddy, deploy.digest(self.caddy_original), b'overwrite')
        self.assertEqual(b'new contents\n', self.caddy.read_bytes())

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
        result = mock.Mock(returncode=1, stdout=('/' + deploy.PLACEHOLDER_TOKEN + '/wsHat').encode('ascii'), stderr=b'diagnostic')
        output = io.StringIO()
        with mock.patch.object(deploy.subprocess, 'run', return_value=result) as run, contextlib.redirect_stdout(output):
            with self.assertRaises(deploy.DeployError) as error:
                deploy.run(self.state, 'validation', ['dummy'])
        self.assertNotIn('secret', str(error.exception))
        self.assertEqual('', output.getvalue())
        self.assertEqual(b'/[REDACTED-PATH-CREDENTIAL]/wsHat\ndiagnostic', (self.state / 'validation.log').read_bytes())
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


if __name__ == '__main__':
    unittest.main()
