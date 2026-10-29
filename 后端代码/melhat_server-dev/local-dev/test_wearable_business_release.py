"""Data-loss and isolation regression tests; no daily services are contacted."""
import copy
import importlib.util
import pathlib
import tempfile
import unittest
import urllib.error
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('wearable_release', pathlib.Path(__file__).with_name('wearable-business-release.py'))
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


def guardian():
    return {'devices': [{'id': value, 'type': 'W' if value == 'RL-W001' else 'H',
                         'source': 'DEMO_WATCH' if value == 'RL-W001' else 'DIRECT_HELMET'}
                        for value in sorted(release.DEVICE_IDS)] + [{'id': 'unexpected-real', 'source': 'DEVICE'}],
            'bindings': [{'id': 'b1', 'deviceId': 'RL-W001', 'personId': 'demo-person', 'end': None}],
            'people': [{'id': 'demo-person', 'name': '旧演示', 'position': [20, 30]}, {'id': 'real-person'}, {'id': 'old-sample'}],
            'vitals': [{'id': 'v1', 'source': 'DEMO_WATCH', 'deviceId': 'RL-W001', 'personId': 'demo-person'},
                       {'id': 'v2', 'source': 'DEMO_WATCH', 'deviceId': 'RL-W002', 'personId': 'old-sample'},
                       {'id': 'v3', 'source': 'DEVICE', 'deviceId': 'real-watch', 'personId': 'real-person'}],
            'events': [{'id': 'real-event', 'source': 'device', 'deviceId': '866652023095053', 'personId': 'real-person'},
                       {'id': 'unknown-event', 'deviceId': 'unknown-device'}, {'id': 'sample-event', 'source': 'demo'}],
            'locations': [{'id': 'historical-point', 'deviceId': '866652021714127'}, {'id': 'new-point', 'source': 'direct-belt'}],
            'works': [{'id': 'old-work', 'source': 'demo'}], 'media': [{'id': 'old-media', 'source': 'demo'}],
            'fences': [{'id': 'F1', 'points': [[1, 1], [2, 2]]}, {'id': 'new-fence', 'source': 'MANUAL'}],
            'groups': [], 'stations': [{'id': 'S1'}, {'id': 'S2'}],
            'sos': {'id': 'real-sos', 'deviceId': '866652023095053'},
            'assistance': {'real-event': {'eventId': 'real-event', 'status': 'waiting'},
                           'sample-event': {'eventId': 'sample-event', 'deviceId': 'RL-H008', 'status': 'waiting'}}}


class CleanupTests(unittest.TestCase):
    def test_three_devices_archive_unknown_and_preserve_all_real_history(self):
        original = guardian()
        clean, archived = release.prune_guardian(original, {})
        self.assertEqual({x['id'] for x in clean['devices']}, release.DEVICE_IDS)
        self.assertTrue(any(x['record'].get('id') == 'unexpected-real' for x in archived))
        self.assertEqual([x['id'] for x in clean['events']], ['real-event'])
        self.assertTrue(any(x['record'].get('id') == 'unknown-event' for x in archived))
        self.assertEqual(clean['locations'], original['locations'])
        self.assertEqual(clean['sos'], original['sos'])
        self.assertEqual(clean['assistance'], {'real-event': original['assistance']['real-event']})
        self.assertEqual({x['id'] for x in clean['people']}, {'demo-person', 'real-person'})
        self.assertEqual([x['id'] for x in clean['vitals']], ['v1', 'v3'])
        self.assertNotIn('position', clean['people'][0])
        self.assertEqual(len(original['devices']), 4, 'Planner must not mutate its input')

    def test_reused_seed_event_id_does_not_remove_modified_real_event(self):
        data = guardian()
        data['events'] = [{'id': 'reused', 'message': 'real edit', 'source': 'PLATFORM'}]
        clean, _ = release.prune_guardian(data, {'events': [{'id': 'reused', 'message': 'sample'}]})
        self.assertEqual(clean['events'], data['events'])

    def test_fake_external_pending_link_is_archived_without_losing_real_event(self):
        data = guardian()
        data['events'][0].update(externalId='BELT-123', externalStatus='待回传')
        clean, archive = release.prune_guardian(data, {})
        event = clean['events'][0]
        self.assertEqual(event['id'], 'real-event')
        self.assertEqual(event['externalId'], '')
        self.assertEqual(event['externalStatus'], '未接入外部系统')
        old = next(row for row in archive if row['collection'] == 'eventExternalPlaceholder')
        self.assertEqual(old['record']['externalId'], 'BELT-123')
        release.unchanged_real_history(data, clean)
        linked, _ = release.prune_guardian(data, {}, external_links={'real-event'})
        self.assertEqual(linked['events'][0]['externalId'], 'BELT-123')

    def test_manual_sos_and_its_assistance_survive_without_hardware_id(self):
        data = guardian()
        data['events'].append({'id': 'manual-sos', 'source': 'manual_sos', 'deviceId': ''})
        data['assistance']['manual-sos'] = {'eventId': 'manual-sos', 'status': 'waiting'}
        clean, _ = release.prune_guardian(data, {})
        self.assertTrue(any(row['id'] == 'manual-sos' for row in clean['events']))
        self.assertIn('manual-sos', clean['assistance'])

    def test_nested_real_business_people_and_portal_ids_preserve_history_associations(self):
        data = guardian()
        additions = ['worker', 'leader', 'supervisor', 'group-person', 'sos-person', 'snapshot-person', 'fence-person']
        data['people'] += [{'id': value, 'station': 'S2'} for value in additions]
        data['works'] = [{'id': 'real-work', 'source': 'PLATFORM', 'members': ['worker'], 'leader': 'leader', 'supervisor': 'supervisor'}]
        data['groups'] = [{'id': 'real-group', 'source': 'MANUAL', 'members': ['group-person']}]
        data['fences'] = [{'id': 'real-fence', 'source': 'MANUAL', 'members': ['fence-person']}]
        data['events'] += [{'id': 'manual', 'source': 'manual_sos', 'personId': 'sos-person',
                            'snapshot': {'person': {'id': 'snapshot-person'}}}]
        clean, _ = release.prune_guardian(data, {})
        self.assertTrue(set(additions) <= {row['id'] for row in clean['people']})
        self.assertEqual({row['id'] for row in clean['stations']}, {'S1', 'S2'})
        original = {'devices': [{'id': value, 'type': 'WATCH' if value == 'RL-W001' else 'HELMET'} for value in release.LEDGER_IDS],
                    'assignments': [{'id': 'a', 'deviceId': 'RL-W001', 'personId': 'demo-person', 'active': True}],
                    'people': [{'id': 'demo-person'}] + [{'id': 'ledger-' + value, 'portalId': value} for value in additions] + [{'id': 'historical-ledger'}],
                    'history': [{'id': 'history', 'personId': 'historical-ledger'}],
                    'accounts': [{'id': 'operator', 'personId': 'ledger-sos-person', 'roleScopes': [{'siteIds': ['site-2']}]}],
                    'roles': [{'id': 'role', 'grants': [{'siteIds': ['site-3']}]}],
                    'sites': [{'id': 'site-2'}, {'id': 'site-3'}],
                    'dutyShifts': [{'id': 'shift', 'personIds': ['ledger-worker', 'discarded-person']}]}
        ledger, _ = release.prune_ledger(original, clean)
        self.assertTrue({'ledger-' + value for value in additions} <= {row['id'] for row in ledger['people']})
        self.assertIn('historical-ledger', {row['id'] for row in ledger['people']})
        self.assertEqual(ledger['accounts'][0]['personId'], 'ledger-sos-person')
        self.assertEqual({row['id'] for row in ledger['sites']}, {'site-2', 'site-3'})
        self.assertEqual(ledger['dutyShifts'][0]['personIds'], ['ledger-worker'])

    def test_simulated_watch_owner_with_real_history_keeps_real_identity(self):
        data = guardian()
        data['events'][0]['personId'] = 'demo-person'
        data['people'][0]['name'] = '真实人员'
        clean, _ = release.prune_guardian(data, {})
        person = next(row for row in clean['people'] if row['id'] == 'demo-person')
        self.assertEqual(person['name'], '真实人员')
        self.assertNotEqual(person.get('source'), 'DEMO_WATCH')

    def test_offline_import_initializes_only_missing_control_and_checks_exact_watermark(self):
        with patch.object(release, 'inspect', return_value={'State': {'Running': False}}), \
             patch.object(release, 'sql', side_effect=[b'9\t0\n', b'']) as database:
            release.prepare_offline_import('qa-mysql', 'qa-backend', {'reportWatermark': 9})
            self.assertIn('ON DUPLICATE KEY UPDATE control_key=control_key', database.call_args[0][1])
            self.assertNotIn("UPDATE mode", database.call_args[0][1])
        with patch.object(release, 'inspect', return_value={'State': {'Running': False}}), \
             patch.object(release, 'sql', return_value=b'10\t0\n') as database:
            with self.assertRaises(RuntimeError):
                release.prepare_offline_import('qa-mysql', 'qa-backend', {'reportWatermark': 9})
            self.assertEqual(database.call_count, 1)

    def test_env_key_update_preserves_all_other_settings_and_line_endings(self):
        import base64
        key = base64.b64encode(b'x' * 32).decode()
        before = '# comment\r\nMEDIA_ENABLED=true\r\nPASSWORD=unchanged\r\nMELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY=old\r\n'
        updated = release.replace_env_key(before, key)
        self.assertEqual(updated, before.replace('KEY=old', 'KEY=' + key))
        self.assertEqual(release.replace_env_key(updated, key), updated)

    def test_missing_or_reassigned_simulated_watch_aborts(self):
        data = guardian()
        data['devices'] = [row for row in data['devices'] if row['id'] != 'RL-W001']
        with self.assertRaises(RuntimeError):
            release.prune_guardian(data, {})
        data = guardian()
        next(row for row in data['devices'] if row['id'] == 'RL-W001')['source'] = 'DEVICE'
        with self.assertRaises(RuntimeError):
            release.prune_guardian(data, {})

    def test_ambiguous_watch_owner_aborts_without_new_bindings(self):
        data = guardian()
        data['bindings'].append({'deviceId': 'RL-W001', 'personId': 'another', 'end': None})
        with self.assertRaises(RuntimeError):
            release.prune_guardian(data, {})

    def test_known_seed_configuration_is_archived_and_manual_retained(self):
        clean, archived = release.prune_guardian(guardian(), {})
        self.assertEqual([row['id'] for row in clean['fences']], ['new-fence'])
        self.assertTrue(any(row['collection'] == 'fences' and row['record']['id'] == 'F1' for row in archived))

    def test_ledger_keeps_credentials_and_real_devices_unassigned(self):
        before = {'devices': [{'id': value, 'type': 'WATCH' if value == 'RL-W001' else 'HELMET'} for value in release.LEDGER_IDS] + [{'id': 'sample'}],
                  'assignments': [{'id': 'assignment', 'deviceId': 'RL-W001', 'personId': 'demo-person', 'active': True}],
                  'people': [{'id': 'demo-person'}, {'id': 'sample-person'}],
                  'accounts': [{'id': 'account', 'personId': 'sample-person', 'credential': 'keep-hash', 'siteId': 'site-1'}],
                  'roles': [{'id': 'role', 'permissions': ['device:read']}], 'sites': [{'id': 'site-1'}]}
        clean_guardian, _ = release.prune_guardian(guardian(), {})
        after, archive = release.prune_ledger(before, clean_guardian)
        self.assertEqual({row['id'] for row in after['devices']}, release.LEDGER_IDS)
        self.assertIsNone(after['accounts'][0]['personId'])
        self.assertEqual(after['accounts'][0]['credential'], 'keep-hash')
        self.assertEqual(after['roles'], before['roles'])
        self.assertEqual(after['assignments'], before['assignments'])
        self.assertTrue(any(row['collection'] == 'accountAssociation' for row in archive))

    def test_cleanup_uses_exact_seen_ids_not_sweep_and_never_deletes_report_history(self):
        before = {'devices': [{'id': 'old', 'name': "a' ; DROP TABLE x;"}], 'accounts': []}
        after = {'devices': [], 'accounts': []}
        query = release.ledger_cleanup_sql(before, after, [], 'test')
        self.assertIn('DELETE FROM `wearable_device` WHERE id=CONVERT(0x6f6c64', query)
        self.assertNotIn('NOT IN', query)
        self.assertNotIn('DROP TABLE', query)
        self.assertNotIn('wearable_device_report', query)

    def test_dump_row_counts_include_empty_tables_and_one_insert_per_row(self):
        dump = b'CREATE TABLE `wearable_device` (\n);\nINSERT INTO `wearable_device` VALUES (1);\nINSERT INTO `wearable_device` VALUES (2);\nCREATE TABLE `empty` (\n);\n'
        self.assertEqual(release.dump_counts(dump), {'wearable_device': 2, 'empty': 0})

    def test_qa_replaces_every_live_connection_and_all_integration_switches(self):
        options = release.isolated_command(['--spring.redis.host=live', '--spring.datasource.druid.master.url=live',
                                           '--melhat.direct.enabled=true', '--melhat.belt.enabled=true',
                                           '--melhat.helmet-media.enabled=true', '--keep=ok'], 'qa-db', 'qa-redis', 'test-only')
        self.assertIn('--spring.redis.host=qa-redis', options)
        self.assertIn('--melhat.direct.enabled=false', options)
        self.assertIn('--melhat.belt.enabled=false', options)
        self.assertIn('--melhat.helmet-media.enabled=false', options)
        self.assertNotIn('--spring.redis.host=live', options)
        self.assertFalse(any(arg.endswith('=live') for arg in options))

    def test_legacy_cleanup_requires_proven_seed_origin_and_protects_real_device_numbers(self):
        columns = {'safety_hat_info': ['id', 'hat_number', 'create_by'],
                   'safety_hat_location_record': ['id', 'hat_number', 'create_by'],
                   'demo_compat_record': ['id', 'module_key', 'business_key', 'payload']}
        query = release.old_demo_cleanup_sql('run', columns, {'RL-H001'})
        self.assertIn("create_by='demo'", query)
        self.assertIn("create_by='guardian'", query)
        self.assertIn("JSON_EXTRACT(payload,'$.demo')=true", query)
        for device in release.REAL_DEVICES:
            self.assertIn(release.quote(device), query)
        self.assertNotIn('DELETE FROM `sys_user`', query)
        self.assertNotIn('wearable_device_report', query)

    def test_runtime_recreation_preserves_network_ports_volumes_and_media_key(self):
        current = {'Config': {'Env': ['MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY=old', 'OTHER=kept'], 'Cmd': ['--unchanged=value']},
                   'NetworkSettings': {'Networks': {'daily-network': {}}},
                   'HostConfig': {'RestartPolicy': {'Name': 'unless-stopped'}, 'PortBindings': {'18084/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '18084'}]}},
                   'Mounts': [{'Type': 'volume', 'Name': 'daily-data', 'Destination': '/data', 'RW': True}]}
        args = release.recreate_args(current, 'sha256:verified', 'same-backup-key')
        self.assertIn('daily-network', args)
        self.assertIn('127.0.0.1:18084:18084/tcp', args)
        self.assertIn('daily-data:/data', args)
        self.assertIn('MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY=same-backup-key', args)
        self.assertNotIn('MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY=old', args)
        self.assertIn('MELHAT_DEMO_MODE=false', args)
        self.assertEqual(args[-2:], ['sha256:verified', '--unchanged=value'])

    def test_real_history_comparison_rejects_lost_or_changed_new_reports(self):
        before = guardian()
        after = copy.deepcopy(before)
        after['events'][0]['id'] = 'overwritten'
        with self.assertRaises(RuntimeError):
            release.unchanged_real_history(before, after)

    def test_rollback_uses_newest_export_and_does_not_overwrite_database(self):
        current = {'Id': 'new-container', 'Config': {'Env': [], 'Cmd': []},
                   'NetworkSettings': {'Networks': {'daily': {}}},
                   'HostConfig': {'RestartPolicy': {'Name': 'unless-stopped'}, 'PortBindings': {}}, 'Mounts': []}
        old = copy.deepcopy(current)
        old.update(Id='old-container', State={'Running': False})
        receipt = {'previousContainerName': 'previous', 'previousContainerId': 'old-container',
                   'previousImageId': 'old-image', 'newImageId': 'new-image'}
        copied = []
        commands = []

        def docker(*args, **kwargs):
            commands.append(args)
            if args[0] == 'cp' and str(args[1]).endswith('guardian-state.json'):
                copied.append(release.read_json(pathlib.Path(args[1])))
            return b''

        def export(image, container, key, directory, operation):
            self.assertEqual(operation, 'Export')
            directory.mkdir()
            release.write_json(directory / 'guardian-state.json', {
                'devices': [{'id': value} for value in release.DEVICE_IDS],
                'events': [{'id': 'new-after-release', 'deviceId': '866652023095053'}]})
            release.write_json(directory / 'helmet-media-private.json', {'new-command': True})
            return {'reportWatermark': 105, 'pendingReports': 0}

        with tempfile.TemporaryDirectory() as name:
            folder = pathlib.Path(name)
            (folder / 'baseline').mkdir()
            release.write_json(folder / 'release.json', receipt)
            release.write_json(folder / 'legacy-rollback-acceptance.json', {'passed': True,
                               'emptyCollectionsPreserved': True, 'imageId': receipt['previousImageId']})
            release.write_json(folder / 'baseline/business-keys.private.json', {'MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY': 'same-key'})
            with patch.object(release, 'safe_folder', return_value=folder), \
                 patch.object(release, 'admin_token', return_value='private-token'), \
                 patch.object(release, 'maintenance', return_value={'mode': 'ACTIVE', 'paused': False, 'lastSequence': 105}), \
                 patch.object(release, 'wait_replayed'), \
                 patch.object(release, 'inspect', side_effect=lambda value: old if value == 'previous' else current), \
                 patch.object(release, 'run', side_effect=docker), patch.object(release, 'sql') as sql, \
                 patch.object(release, 'dump', return_value=b'CURRENT SQL'), \
                 patch.object(release, 'business_cli', side_effect=export), patch.object(release, 'healthy'):
                result = release.rollback(folder, 'token-file')
                sql.assert_not_called()
            self.assertEqual(copied[0]['events'][0]['id'], 'new-after-release')
            self.assertEqual(result['rollbackReportWatermark'], 105)
            starts = [cmd for cmd in commands if cmd[0] == 'run']
            self.assertEqual(len(starts), 1)
            self.assertIn('MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY=same-key', starts[0])

    def test_missing_administrator_session_fails_before_any_docker_mutation(self):
        with patch.object(release, 'run') as docker:
            with self.assertRaises(RuntimeError):
                release.admin_token(None)
            docker.assert_not_called()

    def test_release_rejects_changed_cleanup_or_acceptance_script_before_docker_mutation(self):
        with tempfile.TemporaryDirectory() as name:
            folder = pathlib.Path(name)
            metadata = {'ready': True, 'restoreVerified': True, 'cleanupVerified': True,
                        'acceptanceVerified': True, 'imageId': 'image', 'acceptanceImageId': 'image',
                        'cleanupToolSha256': release.script_hash(),
                        'acceptanceToolSha256': release.script_hash('verify-wearable-business-stage.py')}
            for field in ('cleanupToolSha256', 'acceptanceToolSha256'):
                changed = dict(metadata, **{field: 'stale-hash'})
                release.write_json(folder / 'stage.json', changed)
                with patch.object(release, 'safe_folder', return_value=folder), \
                     patch.object(release, 'admin_token', return_value='private'), \
                     patch.object(release, 'admin_api', return_value={'state': {'accounts': [{'id': 'demo-system'}]}}), \
                     patch.object(release, 'run') as docker:
                    with self.assertRaisesRegex(RuntimeError, 'changed after rehearsal'):
                        release.release(folder, 'token')
                    docker.assert_not_called()

    def test_rollback_pending_report_restarts_sql_writer_without_starting_old_image(self):
        receipt = {'previousContainerName': 'previous', 'previousContainerId': 'old-id',
                   'previousImageId': 'old-image', 'newImageId': 'new-image'}
        with tempfile.TemporaryDirectory() as name:
            folder = pathlib.Path(name)
            (folder / 'baseline').mkdir()
            release.write_json(folder / 'release.json', receipt)
            release.write_json(folder / 'legacy-rollback-acceptance.json', {'passed': True, 'emptyCollectionsPreserved': True, 'imageId': 'old-image'})
            release.write_json(folder / 'baseline/business-keys.private.json', {'MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY': 'same-key'})
            with patch.object(release, 'safe_folder', return_value=folder), \
                 patch.object(release, 'admin_token', return_value='private-token'), \
                 patch.object(release, 'inspect', side_effect=lambda n: {'Id': 'old-id', 'State': {'Running': False}} if n == 'previous' else {'Image': 'new-image'}), \
                 patch.object(release, 'maintenance', return_value={'mode': 'ACTIVE', 'paused': False, 'lastSequence': 11}), \
                 patch.object(release, 'wait_replayed') as replay, patch.object(release, 'healthy') as healthy, \
                 patch.object(release, 'run') as docker, patch.object(release, 'dump', return_value=b'CURRENT'), \
                 patch.object(release, 'business_cli', side_effect=RuntimeError('Pending after stop')):
                with self.assertRaisesRegex(RuntimeError, 'current SQL backend restarted'):
                    release.rollback(folder, 'token')
                docker.assert_any_call('start', release.LIVE)
                self.assertFalse(any(call.args[0] in ('run', 'rename') for call in docker.call_args_list))
                healthy.assert_called_once_with(18084)
                self.assertEqual(replay.call_count, 2)

    def test_pause_waits_for_inflight_writes_after_http_drain_timeout(self):
        statuses = [release.AdminApiError(503), {'mode': 'PAUSED', 'paused': True, 'quiescent': False, 'activeWrites': 1},
                    {'mode': 'PAUSED', 'paused': True, 'quiescent': True, 'activeWrites': 0}]
        with patch.object(release, 'admin_api', side_effect=statuses), patch.object(release.time, 'sleep'):
            state = release.maintenance('private-token', 'PAUSED')
        self.assertTrue(state['quiescent'])

    def test_lazy_guardian_and_media_are_read_initialized_before_pause_without_device_commands(self):
        with tempfile.TemporaryDirectory() as name:
            directory = pathlib.Path(name)
            release.write_json(directory / 'helmet-media-private.json', {'calls': {'HC-original': {'id': 'HC-original'}}})
            with patch.object(release, 'maintenance', return_value={'mode': 'ACTIVE', 'paused': False}) as control, \
                 patch.object(release, 'business_namespaces', side_effect=[{}, {'guardian': 1, 'media': 1}]), \
                 patch.object(release, 'admin_api') as admin, patch.object(release, 'guardian_local_api') as guardian_api, \
                 patch.object(release, 'local_portal_token') as login:
                receipt = release.initialize_business_stores('admin-session', directory, 'portal-session')
                control.assert_called_once_with('admin-session')
                admin.assert_called_once_with('admin-session', 'query', {'kind': 'devices', 'input': {'siteId': 'site-1', 'pageNum': 1, 'pageSize': 50}})
                guardian_api.assert_called_once_with('helmet/calls/HC-original', 'portal-session', allow_missing=True)
                login.assert_not_called()
                self.assertEqual(receipt['namespaces'], {'guardian': 1, 'media': 1})

    def test_empty_media_uses_only_missing_call_probe_and_can_login_locally(self):
        with tempfile.TemporaryDirectory() as name:
            directory = pathlib.Path(name)
            release.write_json(directory / 'helmet-media-private.json', {})
            with patch.object(release, 'maintenance', return_value={'mode': 'ACTIVE', 'paused': False}), \
                 patch.object(release, 'business_namespaces', side_effect=[{'guardian': 4}, {'guardian': 4, 'media': 1}]), \
                 patch.object(release, 'local_portal_token', return_value='local-session') as login, \
                 patch.object(release, 'guardian_local_api', return_value=None) as guardian_api:
                release.initialize_business_stores('admin-session', directory)
                login.assert_called_once_with()
                guardian_api.assert_called_once_with('helmet/calls/wearable-storage-initialization-missing-call', 'local-session', allow_missing=True)
            with patch.object(release, 'maintenance', return_value={'mode': 'ACTIVE', 'paused': False}), \
                 patch.object(release, 'business_namespaces', return_value={'guardian': 4}), \
                 patch.object(release, 'guardian_local_api', return_value={}):
                with self.assertRaisesRegex(RuntimeError, 'must be a missing call'):
                    release.initialize_business_stores('admin-session', directory, 'portal-session')

    def test_initialization_requires_actual_sql_markers_and_refuses_to_initialize_while_paused(self):
        with tempfile.TemporaryDirectory() as name:
            directory = pathlib.Path(name)
            release.write_json(directory / 'helmet-media-private.json', {})
            with patch.object(release, 'maintenance', return_value={'mode': 'ACTIVE', 'paused': False}) as control, \
                 patch.object(release, 'business_namespaces', return_value={'guardian': 2}), \
                 patch.object(release, 'guardian_local_api', return_value=None):
                with self.assertRaisesRegex(RuntimeError, 'both initialize before maintenance pause'):
                    release.initialize_business_stores('admin-session', directory, 'portal-session')
                control.assert_called_once_with('admin-session')
            with patch.object(release, 'maintenance', return_value={'mode': 'PAUSED', 'paused': True}), \
                 patch.object(release, 'admin_api') as admin, patch.object(release, 'guardian_local_api') as guardian_api:
                with self.assertRaisesRegex(RuntimeError, 'while.*ACTIVE'):
                    release.initialize_business_stores('admin-session', directory, 'portal-session')
                admin.assert_not_called(); guardian_api.assert_not_called()

    def test_initialized_stores_do_not_read_legacy_files_or_create_a_new_session(self):
        with patch.object(release, 'maintenance', return_value={'mode': 'ACTIVE', 'paused': False}), \
             patch.object(release, 'business_namespaces', return_value={'guardian': 7, 'media': 3}), \
             patch.object(release, 'admin_api') as admin, patch.object(release, 'guardian_local_api') as guardian_api, \
             patch.object(release, 'read_json') as read, patch.object(release, 'local_portal_token') as login:
            receipt = release.initialize_business_stores('admin-session', pathlib.Path('unused'))
            self.assertFalse(receipt['guardianReadRequired']); self.assertFalse(receipt['mediaReadRequired'])
            admin.assert_not_called(); guardian_api.assert_not_called(); read.assert_not_called(); login.assert_not_called()

    def test_local_initialization_accepts_only_expected_missing_record_and_rejects_redirects(self):
        for status in (401, 403, 500):
            error = urllib.error.HTTPError('http://127.0.0.1:18084/test', status, 'rejected', {}, None)
            with patch.object(release.urllib.request, 'build_opener') as opener:
                opener.return_value.open.side_effect = error
                with self.assertRaisesRegex(RuntimeError, 'HTTP ' + str(status)):
                    release.guardian_local_api('helmet/calls/missing', 'private-token', allow_missing=True)
                request = opener.return_value.open.call_args.args[0]
                self.assertTrue(request.full_url.startswith('http://127.0.0.1:18084/api/guardian/v1/'))
                self.assertEqual(request.get_method(), 'GET')
        with patch.object(release.urllib.request, 'build_opener') as opener:
            opener.return_value.open.side_effect = urllib.error.HTTPError('http://127.0.0.1:18084/test', 404, 'missing', {}, None)
            self.assertIsNone(release.guardian_local_api('helmet/calls/missing', 'private-token', allow_missing=True))
        with self.assertRaisesRegex(RuntimeError, 'must not redirect'):
            release.NoLocalRedirect().redirect_request(None, None, 302, 'redirect', {}, 'https://remote.invalid')

    def test_release_installs_compatibility_before_online_cleanup_and_stops_only_once(self):
        operations = []
        current = {'Id': 'old-container', 'Image': 'old-image', 'Config': {'Env': [], 'Cmd': []},
                   'NetworkSettings': {'Networks': {'daily': {}}},
                   'HostConfig': {'RestartPolicy': {'Name': 'unless-stopped'}, 'PortBindings': {}}, 'Mounts': []}
        upgraded = copy.deepcopy(current)
        upgraded.update(Id='new-container', Image='new-image')
        inventory = {'devices': [{'id': value, 'type': 'WATCH' if value == 'RL-W001' else 'HELMET'} for value in release.LEDGER_IDS],
                     'assignments': [{'id': 'assignment', 'deviceId': 'RL-W001', 'personId': 'demo-person', 'active': True}],
                     'people': [{'id': 'demo-person'}], 'accounts': [{'id': 'demo-system', 'siteId': 'site-1'}], 'roles': [], 'sites': [{'id': 'site-1'}]}
        started = False

        def docker(*args, **kwargs):
            nonlocal started
            operations.append(args[0])
            if args[0] == 'run':
                started = True
            return b''

        def observe(name):
            if name == 'qa-backend':
                return {'Image': 'new-image'}
            return upgraded if started else current

        def control(token, mode=None):
            operations.append('maintenance:' + str(mode))
            return {'mode': mode or 'PAUSED', 'paused': mode != 'ACTIVE', 'quiescent': True, 'activeWrites': 0, 'lastSequence': 100}

        def cli(image, container, key, directory, operation, require_drained=True):
            operations.append(operation)
            if operation == 'Export':
                self.assertTrue(started)
                self.assertFalse(require_drained, 'Paused raw reports may continue arriving')
                directory.mkdir()
                release.write_json(directory / 'guardian-state.json', guardian())
                release.write_json(directory / 'helmet-media-private.json', {})
                return {'guardianInitialized': True, 'guardianRevision': 1, 'mediaRevision': 1, 'reportWatermark': 99, 'pendingReports': 8}
            return {'guardianRevision': 2, 'reportWatermark': 100}

        with tempfile.TemporaryDirectory() as name:
            folder = pathlib.Path(name)
            (folder / 'baseline').mkdir()
            release.write_json(folder / 'stage.json', {'ready': True, 'restoreVerified': True, 'cleanupVerified': True,
                               'imageId': 'new-image', 'backend': 'qa-backend',
                               'acceptanceVerified': True, 'acceptanceImageId': 'new-image',
                               'cleanupToolSha256': release.script_hash(),
                               'acceptanceToolSha256': release.script_hash('verify-wearable-business-stage.py')})
            release.write_json(folder / 'baseline/business-keys.private.json', {'MELHAT_BUSINESS_MEDIA_ENCRYPTION_KEY': 'same-key'})
            with patch.object(release, 'safe_folder', return_value=folder), \
                 patch.object(release, 'admin_token', return_value='private-token'), \
                 patch.object(release, 'admin_api', return_value={'state': {'accounts': [{'id': 'demo-system'}]}}), \
                 patch.object(release, 'inspect', side_effect=observe), patch.object(release, 'run', side_effect=docker), \
                 patch.object(release, 'dump', return_value=b'CURRENT SQL'), patch.object(release, 'business_initialized', return_value=False), \
                 patch.object(release, 'current_authority', return_value={'mode': 'auto'}), \
                 patch.object(release, 'business_cli', side_effect=cli), patch.object(release, 'healthy'), \
                 patch.object(release, 'initialize_business_stores', side_effect=lambda *args: operations.append('initialize-stores') or {'namespaces': {'guardian': 1, 'media': 1}}), \
                 patch.object(release, 'maintenance', side_effect=control), \
                 patch.object(release, 'ledger_snapshot', return_value=inventory), \
                 patch.object(release, 'external_references', return_value=set()), \
                 patch.object(release, 'legacy_columns', return_value={}), \
                 patch.object(release, 'sql', side_effect=lambda *args: operations.append('cleanup-sql')), \
                 patch.object(release, 'rows', return_value=inventory['devices']), \
                 patch.object(release, 'wait_replayed') as replay:
                result = release.release(folder, 'token-file')
                replay.assert_called_once_with(100)
            self.assertEqual(result['status'], 'released')
            self.assertEqual(operations.count('stop'), 1)
            self.assertLess(operations.index('run'), operations.index('maintenance:PAUSED'))
            self.assertLess(operations.index('run'), operations.index('initialize-stores'))
            self.assertLess(operations.index('initialize-stores'), operations.index('maintenance:PAUSED'))
            self.assertLess(operations.index('maintenance:PAUSED'), operations.index('cleanup-sql'))
            self.assertLess(operations.index('cleanup-sql'), operations.index('Import'))
            self.assertLess(operations.index('Import'), operations.index('maintenance:ACTIVE'))

    def test_paths_cannot_escape_release_directory(self):
        for path in (release.ROOT, release.BUILD / '../elsewhere', release.BUILD / 'wearable-release-unverified'):
            with self.assertRaises(RuntimeError):
                release.safe_folder(path)


if __name__ == '__main__':
    unittest.main()
