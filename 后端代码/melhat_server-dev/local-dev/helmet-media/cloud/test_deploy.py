import tempfile
import unittest
import contextlib
import io
from pathlib import Path
from unittest import mock
import deploy

class DeploymentTests(unittest.TestCase):
    def reviewed_multisite(self):
        token = 'a' * 43
        prefix = '{\n    admin off\n}\n\n'
        body = ('    encode zstd gzip\n'
                '    @helmet_device path /' + token + '/api/index.php /' + token + '/wsHat\n'
                '    handle @helmet_device {\n        reverse_proxy 10.255.1.1:28086\n    }\n'
                '    @belt_device path /belt-token/api/belt/index.php /belt-token/api/belt/config/index.php /belt-token/wsBelt\n'
                '    handle @belt_device {\n        reverse_proxy 10.255.1.1:28087\n    }\n'
                '    handle {\n        reverse_proxy nginx:80\n    }\n')
        suffix = ('\nwww.{$DOMAIN} {\n    handle /baidu_verify_test.html {\n        respond "reviewed verification"\n    }\n'
                  '    handle {\n        redir https://{$DOMAIN}{uri}\n    }\n}\n\n'
                  'http://39.106.212.138 {\n    @belt_legacy_ws path /belt-token/wsHat\n'
                  '    handle @belt_legacy_ws {\n        reverse_proxy 10.255.1.1:28087\n    }\n'
                  '    handle {\n        respond "Not Found" 404\n    }\n}\n')
        return prefix, body, suffix

    def test_observed_global_www_and_legacy_sites_are_preserved_exactly(self):
        prefix, body, suffix = self.reviewed_multisite()
        old = prefix + '{$DOMAIN} {\n' + body + '}\n' + suffix
        candidate, _ = deploy.candidates(old.encode(), b'UsePAM yes\n', deploy.PLACEHOLDER_TOKEN)
        fragment = (Path(deploy.__file__).parent / 'Caddyfile.fragment').read_text(encoding='utf-8').rstrip('\n') + '\n'
        expected_body = body.replace('/' + 'a'*43 + '/wsHat\n', '/' + 'a'*43 + '/wsHat /' + 'a'*43 + '/api/upload\n')
        expected_body = expected_body.replace('    handle {\n        reverse_proxy nginx:80\n    }\n', fragment + '    handle {\n        reverse_proxy nginx:80\n    }\n')
        self.assertEqual((prefix + '{$DOMAIN} {\n' + expected_body + '}\n' + suffix).encode(), candidate)

    def test_matching_fallback_outside_main_site_is_neither_counted_nor_modified(self):
        prefix, body, suffix = self.reviewed_multisite()
        outside = 'other.example {\n' + body + '}\n'
        old = prefix + outside + '{$DOMAIN} {\n' + body + '}\n' + suffix + outside
        candidate, _ = deploy.candidates(old.encode(), b'', deploy.PLACEHOLDER_TOKEN)
        self.assertTrue(candidate.startswith((prefix + outside + '{$DOMAIN} {\n').encode()))
        self.assertTrue(candidate.endswith((suffix + outside).encode()))
        self.assertEqual(1, candidate.count(b'/api/upload'))

    def test_outside_fallback_or_helmet_cannot_substitute_for_missing_main_route(self):
        prefix, body, suffix = self.reviewed_multisite()
        outside = 'other.example {\n' + body + '}\n'
        for changed in [body.replace('reverse_proxy nginx:80', 'reverse_proxy unreviewed:80'),
                        body.replace('@helmet_device path', '@different_device path')]:
            with self.subTest(body=changed[:30]), self.assertRaises(deploy.DeployError):
                deploy.candidates((prefix + '{$DOMAIN} {\n' + changed + '}\n' + outside + suffix).encode(), b'', deploy.PLACEHOLDER_TOKEN)

    def test_duplicate_main_sites_and_unknown_boundaries_are_rejected(self):
        prefix, body, suffix = self.reviewed_multisite()
        site = '{$DOMAIN} {\n' + body + '}\n'
        for changed in [site + site, site.replace('}\n', '} # unsupported boundary\n'),
                        site.replace('{$DOMAIN} {\n', '{$DOMAIN}\n{\n'),
                        site.replace('    encode zstd gzip\n', 'unreviewed.example {\n')]:
            with self.subTest(site=changed[:50]), self.assertRaises(deploy.DeployError):
                deploy.candidates((prefix + changed + suffix).encode(), b'', deploy.PLACEHOLDER_TOKEN)

    def test_nested_fallback_and_duplicate_helmet_matchers_are_rejected(self):
        prefix, body, suffix = self.reviewed_multisite()
        anchor = '    handle {\n        reverse_proxy nginx:80\n    }\n'
        variants = [body.replace(anchor, '    route {\n' + anchor + '    }\n'),
                    body.replace(anchor, '    route {\n' + anchor + '    }\n    handle {\n        respond "different fallback"\n    }\n'),
                    body + '    @helmet_device path /unreviewed/path\n']
        for changed in variants:
            with self.subTest(body=changed[-100:]), self.assertRaises(deploy.DeployError):
                deploy.candidates((prefix + '{$DOMAIN} {\n' + changed + '}\n' + suffix).encode(), b'', deploy.PLACEHOLDER_TOKEN)

    def test_media_marker_anywhere_requires_transaction_inspection(self):
        prefix, body, suffix = self.reviewed_multisite()
        old = (prefix + '{$DOMAIN} {\n' + body + '}\n' + suffix).encode()
        marker = ('# ' + deploy.MARKER + '\n').encode()
        for caddy, ssh in [(old + marker, b''), (old, marker)]:
            with self.assertRaisesRegex(deploy.DeployError, 'marker already exists'):
                deploy.candidates(caddy, ssh, deploy.PLACEHOLDER_TOKEN)

    def test_public_business_prefix_is_removed_only_inside_its_own_handle(self):
        fragment = (Path(deploy.__file__).parent / 'Caddyfile.fragment').read_text(encoding='utf-8')
        self.assertIn('    @wear_business path /wear-api/api/guardian/v1/*\n', fragment)
        self.assertNotIn(' path /api/guardian/v1/', fragment)
        business_start = fragment.index('    handle @wear_business {\n')
        business_end = fragment.index('\n    }\n', business_start)
        business = fragment[business_start:business_end]
        other_routes = fragment[:business_start] + fragment[business_end:]
        self.assertIn('        uri strip_prefix /wear-api\n', business)
        self.assertIn('        reverse_proxy 10.255.1.1:28088 {\n', business)
        self.assertLess(business.index('uri strip_prefix'), business.index('reverse_proxy'))
        self.assertNotIn('strip_prefix', other_routes)
        self.assertNotIn('handle_path', fragment)
        self.assertIn(' path /helmet-media/control/v1/* ', other_routes)
        self.assertIn('reverse_proxy 10.255.1.1:18190', other_routes)
        self.assertIn('header_up -Authorization', business)
        self.assertIn('header_up -Cookie', business)
        self.assertNotIn('18084', fragment)

    def test_candidate_preserves_helmet_belt_and_remaining_site(self):
        token='a'*43
        old=('{$DOMAIN} {\n    encode zstd gzip\n    @helmet_device path /'+token+'/api/index.php /'+token+'/wsHat\n'
          '    handle @helmet_device {\n        reverse_proxy 10.255.1.1:28086\n    }\n'
          '    @belt_device path /belt-keep/wsHat\n    handle @belt_device {\n        reverse_proxy 10.255.1.1:28087\n    }\n'
          '    handle {\n        reverse_proxy nginx:80\n    }\n}\nwww.{$DOMAIN} { redir https://{$DOMAIN}{uri} }\n').encode()
        ssh=b'Port 22\nUsePAM yes\nMatch User helmet-tunnel\n    PermitListen 10.255.1.1:28086\n'
        candidate,updated=deploy.candidates(old,ssh,deploy.PLACEHOLDER_TOKEN)
        self.assertIn(b'28086',candidate);self.assertIn(b'28087',candidate);self.assertIn(b'28088',candidate)
        self.assertIn(('/'+token+'/api/upload').encode(),candidate)
        self.assertIn(b'/helmet-media/control/v1/*',candidate);self.assertNotIn(b'handle_path',candidate)
        self.assertTrue(updated.startswith(ssh));self.assertIn(b'MaxSessions 0',updated)
        self.assertTrue(candidate.endswith(b'www.{$DOMAIN} { redir https://{$DOMAIN}{uri} }\n'))
        with self.assertRaises(deploy.DeployError):deploy.candidates(candidate,updated,deploy.PLACEHOLDER_TOKEN)
    def test_unknown_baseline_rejected(self):
        with self.assertRaises(deploy.DeployError):deploy.candidates(b'other site',b'',deploy.PLACEHOLDER_TOKEN)
    def test_owned_in_place_update_preserves_inode_and_rejects_concurrent_change(self):
        with tempfile.TemporaryDirectory() as directory:
            file=Path(directory)/'Caddyfile';file.write_bytes(b'original');inode=file.stat().st_ino
            deploy.write_in_place(file,deploy.digest(b'original'),b'candidate',inode)
            self.assertEqual(inode,file.stat().st_ino)
            with self.assertRaises(deploy.DeployError):deploy.write_in_place(file,deploy.digest(b'original'),b'overwritten',inode)
            self.assertEqual(b'candidate',file.read_bytes())
class ResumeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.media = self.root / 'media'
        (self.media / '.local/freeswitch').mkdir(parents=True)
        (self.media / 'Dockerfile').write_bytes(b'FROM reviewed-base\n')
        (self.media / 'server.mjs').write_bytes(b'// reviewed code\n')
        for name in ['media.env', 'secrets.json', 'srs.conf', 'turn.conf', 'cloud-settings.json']:
            (self.media / '.local' / name).write_text('synthetic-private-input')
        (self.media / '.local/freeswitch/freeswitch.xml').write_text('<document/>')
        self.caddy = self.root / 'Caddyfile'
        self.sshd = self.root / 'sshd_config'
        self.caddy.write_bytes(('{$DOMAIN} {\n    @helmet_device path /' + 'a'*43 + '/api/index.php /' + 'a'*43 + '/wsHat\n    handle {\n        reverse_proxy nginx:80\n    }\n}\n').encode())
        self.sshd.write_bytes(b'Port 22\nUsePAM yes\n')
        self.state = self.root / 'state'
        self.state.mkdir()
        self.patches = [mock.patch.object(deploy, 'INSTALL_ROOT', self.media),
                        mock.patch.object(deploy, 'CADDY', self.caddy), mock.patch.object(deploy, 'SSHD', self.sshd)]
        for patch in self.patches:
            patch.start()
        caddy, caddy_meta = deploy.snapshot(self.caddy)
        sshd, ssh_meta = deploy.snapshot(self.sshd)
        (self.state / 'original.Caddyfile').write_bytes(caddy)
        (self.state / 'original.sshd_config').write_bytes(sshd)
        self.plan = {'version':1, 'targetIp':deploy.TARGET_IP, 'domain':deploy.DOMAIN, 'service':'sshd.service',
                     'scriptSha256':deploy.digest(Path(deploy.__file__).read_bytes() + (Path(deploy.__file__).parent / 'Caddyfile.fragment').read_bytes()),
                     'installationRoot':str(self.media), 'installationInputs':deploy.installation_inputs(),
                     'original':{'caddy':caddy_meta, 'sshd':ssh_meta}}
        deploy.save_json(self.state / 'preview.json', self.plan)

    def tearDown(self):
        for patch in reversed(self.patches):
            patch.stop()
        self.temp.cleanup()

    def test_resume_revalidates_without_replacing_preview_backups_or_active_configuration(self):
        saved = {path:path.read_bytes() for path in [self.caddy,self.sshd,self.state/'preview.json',self.state/'original.Caddyfile',self.state/'original.sshd_config']}
        (self.media / '.local/models').mkdir()
        (self.media / '.local/models/download.partial').write_bytes(b'partial model')
        (self.media / '__pycache__').mkdir()
        (self.media / '__pycache__/generated.pyc').write_bytes(b'cache')
        with mock.patch.object(deploy,'require_absent_user') as account, mock.patch.object(deploy,'port_available') as port, \
             mock.patch.object(deploy,'server_ready',return_value='sshd.service') as server, \
             mock.patch.object(deploy,'validate_candidates') as validate, contextlib.redirect_stdout(io.StringIO()) as output:
            deploy.resume(self.state)
            account.assert_called_once_with();port.assert_called_once_with();server.assert_called_once_with(self.state)
            self.assertEqual('resume',validate.call_args[0][-1])
            self.assertIn('RESUME OK',output.getvalue())
            self.assertNotIn('synthetic-private-input',output.getvalue())
        for path, data in saved.items():
            self.assertEqual(data,path.read_bytes())
        self.assertFalse((self.state/'deployment.json').exists())

    def test_changed_source_or_private_configuration_is_rejected_before_any_external_check(self):
        for relative in ['Dockerfile','server.mjs','.local/media.env','.local/secrets.json','.local/freeswitch/freeswitch.xml']:
            with self.subTest(file=relative):
                path=self.media/relative;original=path.read_bytes();path.write_bytes(original+b' changed')
                try:
                    with mock.patch.object(deploy,'server_ready') as server, self.assertRaisesRegex(deploy.DeployError,'Source or private configuration changed'):
                        deploy.resume(self.state)
                    server.assert_not_called()
                finally:path.write_bytes(original)

    def test_added_or_deleted_source_input_is_not_silently_adopted(self):
        extra=self.media/'unexpected.mjs';extra.write_bytes(b'new code')
        with self.assertRaises(deploy.DeployError):deploy.resume(self.state)
        extra.unlink()
        (self.media/'server.mjs').unlink()
        with self.assertRaises(deploy.DeployError):deploy.resume(self.state)

    def test_changed_cloud_baseline_or_backup_is_rejected(self):
        for path in [self.caddy,self.sshd,self.state/'original.Caddyfile',self.state/'original.sshd_config']:
            with self.subTest(file=path.name):
                original=path.read_bytes();path.write_bytes(original+b' changed')
                try:
                    with self.assertRaisesRegex(deploy.DeployError,'active configuration or its metadata changed'):
                        deploy.resume(self.state)
                finally:path.write_bytes(original)

    def test_every_transaction_state_blocks_resume_and_is_preserved(self):
        for status in ['prepared','account-created','applied','rolled-back','rollback-needs-attention']:
            path=self.state/'deployment.json';deploy.save_json(path,{'status':status});original=path.read_bytes()
            with self.assertRaisesRegex(deploy.DeployError,'deployment transaction exists'):
                deploy.resume(self.state)
            self.assertEqual(original,path.read_bytes())

    def test_unknown_old_or_moved_installation_cannot_resume(self):
        for field,value in [('installationInputs',None),('installationRoot','/somewhere/else'),('scriptSha256','different-script')]:
            plan=dict(self.plan);plan[field]=value;deploy.save_json(self.state/'preview.json',plan)
            with self.assertRaises(deploy.DeployError):deploy.resume(self.state)
        (self.state/'preview.json').unlink()
        with self.assertRaisesRegex(deploy.DeployError,'completed existing preview'):deploy.resume(self.state)
        self.assertFalse((self.state/'preview.json').exists())

    def test_inputs_changed_during_resume_validation_are_detected(self):
        def concurrent_change(*args):
            (self.media/'server.mjs').write_bytes(b'changed while checking')
        with mock.patch.object(deploy,'require_absent_user'),mock.patch.object(deploy,'port_available'), \
             mock.patch.object(deploy,'server_ready',return_value='sshd.service'), \
             mock.patch.object(deploy,'validate_candidates',side_effect=concurrent_change):
            with self.assertRaisesRegex(deploy.DeployError,'Source or private configuration changed'):
                deploy.resume(self.state)

    def test_apply_rechecks_the_same_pinned_inputs(self):
        (self.media/'.local/turn.conf').write_bytes(b'changed config')
        with self.assertRaisesRegex(deploy.DeployError,'Source or private configuration changed'):
            deploy.check_baseline(self.plan,self.state)

if __name__=='__main__':unittest.main()
