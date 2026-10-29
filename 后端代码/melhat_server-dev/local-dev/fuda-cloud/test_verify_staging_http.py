"""Offline verifier tests. These do not open a socket or issue any HTTP request."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('acceptance', HERE / 'verify_staging_http.py')
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class VerifierTest(unittest.TestCase):
    def test_fixed_utc_milliseconds_and_calendar_validation(self):
        verify.timestamp('2026-10-27T08:00:00.000Z')
        verify.timestamp('2024-02-29T23:59:59.999Z')
        verify.timestamp(None, True)
        for invalid in ['2026-02-29T08:00:00.000Z', '2026-10-27T08:00:00Z',
                        '2026-10-27T08:00:00.000+00:00', '2026-10-27T25:00:00.000Z']:
            with self.subTest(value=invalid), self.assertRaises(verify.VerificationFailure):
                verify.timestamp(invalid)

    def test_request_matches_existing_public_signature_vector_without_sending(self):
        vector = json.loads((HERE.parent / 'fuda-api-contract/examples/signature-vector.json').read_text(encoding='utf-8'))
        client = verify.Client('http://127.0.0.1:18089', vector['headers']['X-App-Id'], bytes(range(32)))
        request = client.request('positions', None, raw=vector['bodyUtf8'].encode(),
            timestamp=vector['headers']['X-Timestamp'], nonce=vector['headers']['X-Nonce'])
        self.assertEqual(vector['expectedSignature'], request.get_header('X-signature'))
        self.assertEqual(vector['bodyUtf8'].encode(), request.data)

    def test_daily_ports_public_targets_credentials_and_redirect_targets_not_allowed(self):
        for url in ['http://127.0.0.1:18084', 'http://127.0.0.1:18086', 'https://example.com:8443',
                    'http://192.168.1.1:18089', 'http://user:password@127.0.0.1:18089',
                    'http://127.0.0.1:18089/api', 'http://127.0.0.1:18089?x=1']:
            with self.subTest(url=url), self.assertRaises(verify.VerificationFailure):
                verify.loopback_origin(url)
        self.assertEqual('http://127.0.0.1:18089', verify.loopback_origin('http://127.0.0.1:18089/'))
        self.assertIsNone(verify.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://example.com'))

    def test_history_deduplicates_retries_and_cursor_advances_to_empty_tail(self):
        a = verify.Acceptance(None, verify.DEFAULT_DEVICES)
        p1 = ({'items': [1], 'nextCursor': 'cursor-1', 'hasMore': True}, {'identity1': 'payload1'})
        p2 = ({'items': [2], 'nextCursor': 'cursor-2', 'hasMore': False}, {'identity2': 'payload2'})
        tail = ({'items': [], 'nextCursor': 'cursor-2', 'hasMore': False}, {})
        with patch.object(a, 'alarm_page', side_effect=[p1, p1, p2, tail]):
            a.history()
        self.assertEqual(2, len(a.events))
        self.assertEqual('cursor-2', a.final_cursor)
        self.assertEqual(1, a.observations['firstPageRepeatedEvents'])

    def test_empty_history_is_not_mislabeled_as_real_alarm_acceptance(self):
        a = verify.Acceptance(None, verify.DEFAULT_DEVICES)
        empty = ({'items': [], 'nextCursor': 'empty-cursor', 'hasMore': False}, {})
        with patch.object(a, 'alarm_page', side_effect=[empty, empty, empty]), self.assertRaises(verify.VerificationFailure):
            a.history()
        self.assertFalse(a.observations['nonemptyAlarmRepeatExercised'])

    def test_resume_requires_old_immutable_events_and_complete_new_set(self):
        client = type('FakeClient', (), {'app': 'test-app'})()
        a = verify.Acceptance(client, verify.DEFAULT_DEVICES)
        checkpoint = {'version': 1, 'applicationHash': verify.fingerprint(client.app),
            'deviceScopeHash': verify.fingerprint(a.devices), 'events': {'old': 'original'}, 'cursor': 'old-cursor'}
        a.events = {'old': 'original', 'new': 'new-payload'}
        tail = ({'items': [1], 'nextCursor': 'next-cursor', 'hasMore': False}, {'new': 'new-payload'})
        with patch.object(a, 'alarm_page', return_value=tail):
            a.resumed(checkpoint, 1)
        self.assertEqual(1, a.observations['resumedNewAlarms'])
        a.events['old'] = 'changed'
        with self.assertRaises(verify.VerificationFailure):
            a.resumed(checkpoint, 0)

    def test_unexpected_failure_report_does_not_print_secret_or_response(self):
        a = verify.Acceptance(None, verify.DEFAULT_DEVICES)
        def fail():
            raise RuntimeError('secret-value and private device body')
        self.assertFalse(a.check('private_failure', fail))
        result = json.dumps(a.checks)
        self.assertNotIn('secret-value', result)
        self.assertIn('RuntimeError', result)

    def test_checkpoint_writer_never_overwrites_existing_evidence(self):
        with tempfile.TemporaryDirectory(dir=HERE) as directory:
            self.assertEqual(Path(directory).resolve().parent, HERE.resolve())
            file = Path(directory) / 'checkpoint.json'
            verify.write_private_new(file, {'cursor': 'opaque'})
            with self.assertRaises(verify.VerificationFailure):
                verify.write_private_new(file, {'cursor': 'new'})
            self.assertEqual({'cursor': 'opaque'}, verify.private_json(file))


if __name__ == '__main__':
    unittest.main()
