"""Offline framing regression tests: never invoke Docker or the real QA relay."""
import contextlib
import http.client
import importlib.util
import io
from pathlib import Path
import threading
import unittest
from email.message import Message
from types import SimpleNamespace
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('qa_proxy', Path(__file__).with_name('work-business-qa-proxy.py'))
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)


def headers(**values):
    result = Message()
    for name, value in values.items():
        result[name.replace('_', '-')] = value
    return result


class BodyTests(unittest.TestCase):
    def decode(self, body, **values):
        return proxy.read_body(headers(**values), io.BytesIO(body))

    def rejected(self, body, status=400, **values):
        with self.assertRaises(proxy.InvalidBody) as raised:
            self.decode(body, **values)
        self.assertEqual(raised.exception.status, status)

    def test_content_length_binary_is_unchanged(self):
        data = b'\x89PNG\r\n\x1a\n\x00\xff'
        self.assertEqual(self.decode(data, Content_Length=str(len(data))), data)

    def test_no_body_and_explicit_empty_body(self):
        self.assertIsNone(self.decode(b''))
        self.assertEqual(self.decode(b'', Content_Length='0'), b'')

    def test_chunked_binary_extensions_and_trailers(self):
        body = b'4;name=value;quoted="a\\\"b"\r\n\x89PNG\r\n2 ; flag\r\n\x00\xff\r\n0;end=yes\r\nX-Checksum: ignored\r\n\r\n'
        self.assertEqual(self.decode(body, Transfer_Encoding='Chunked'), b'\x89PNG\x00\xff')

    def test_empty_chunked_body(self):
        self.assertEqual(self.decode(b'0\r\n\r\n', Transfer_Encoding='chunked'), b'')

    def test_exact_limit_accepts_both_framings(self):
        with patch.object(proxy, 'MAX_BODY', 4):
            self.assertEqual(self.decode(b'abcd', Content_Length='4'), b'abcd')
            self.assertEqual(self.decode(b'2\r\nab\r\n2\r\ncd\r\n0\r\n\r\n', Transfer_Encoding='chunked'), b'abcd')

    def test_oversized_rejected_before_body_read(self):
        self.rejected(b'', 413, Content_Length=str(proxy.MAX_BODY + 1))
        self.rejected(f'{proxy.MAX_BODY + 1:x}\r\n'.encode(), 413, Transfer_Encoding='chunked')
        with patch.object(proxy, 'MAX_BODY', 4):
            self.rejected(b'3\r\nabc\r\n2\r\n', 413, Transfer_Encoding='chunked')

    def test_invalid_content_lengths(self):
        for value in ('-1', '+1', '1x', '1, 1', '', '1.0'):
            with self.subTest(value=value):
                self.rejected(b'', Content_Length=value)
        duplicate = headers(Content_Length='0')
        duplicate['Content-Length'] = '0'
        with self.assertRaises(proxy.InvalidBody):
            proxy.read_body(duplicate, io.BytesIO())

    def test_ambiguous_or_unsupported_encodings(self):
        self.rejected(b'', Content_Length='0', Transfer_Encoding='chunked')
        for value in ('gzip', 'gzip, chunked', 'chunked, chunked', ''):
            self.rejected(b'', Transfer_Encoding=value)

    def test_malformed_chunk_sizes_and_extensions(self):
        for line in (b'-1', b'+1', b'0x1', b'gg', b'1;', b'1;name=', b'1;q="unterminated', b'1;bad name'):
            with self.subTest(line=line):
                self.rejected(line + b'\r\n', Transfer_Encoding='chunked')

    def test_truncated_bodies_and_missing_crlf(self):
        self.rejected(b'ab', Content_Length='3')
        for data in (b'1', b'1\nA\r\n0\r\n\r\n', b'3\r\nab', b'1\r\naXX', b'0\r\n'):
            self.rejected(data, Transfer_Encoding='chunked')

    def test_malformed_or_forbidden_trailers(self):
        for trailer in (b'invalid', b'Content-Length: 2', b'Transfer-Encoding: chunked', b'Host: other', b'X-Test: a\x00b'):
            self.rejected(b'0\r\n' + trailer + b'\r\n\r\n', Transfer_Encoding='chunked')

    def test_framing_lines_and_trailers_are_bounded(self):
        self.rejected(b'1;x=' + b'a' * proxy.MAX_LINE + b'\r\n', Transfer_Encoding='chunked')
        with patch.object(proxy, 'MAX_TRAILERS', 10):
            self.rejected(b'0\r\nX-A: abcdef\r\n\r\n', Transfer_Encoding='chunked')


@contextlib.contextmanager
def local_handler():
    server = proxy.http.server.ThreadingHTTPServer(('127.0.0.1', 0), proxy.Handler)
    server.backend = 'wearable-compatible-qa-test-backend-http'
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        yield server.server_address[1]
    finally:
        server.shutdown()
        server.server_close()
        worker.join()


class HandlerTests(unittest.TestCase):
    def test_real_chunked_put_forwards_decoded_png_once(self):
        png = b'\x89PNG\r\n\x1a\n\x00\xff'
        result = SimpleNamespace(returncode=0, stdout=b'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{"ok":true}')
        with patch.object(proxy.subprocess, 'run', return_value=result) as run, local_handler() as port:
            conn = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
            conn.request('PUT', '/api/guardian/v1/mobile/photo', body=iter([png[:4], png[4:]]),
                         headers={'Content-Type': 'image/png', 'X-Wearable-Token': 'test-only'}, encode_chunked=True)
            response = conn.getresponse()
            self.assertEqual(response.status, 200)
            self.assertEqual(response.read(), b'{"ok":true}')
            conn.close()
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.kwargs['input'], png)
            command = run.call_args.args[0]
            self.assertIn('--data-binary', command)
            self.assertEqual(command[-1], 'http://127.0.0.1:18084/api/guardian/v1/mobile/photo')
            self.assertFalse(any('transfer-encoding' in arg.lower() for arg in command))

    def test_bad_or_oversized_request_never_invokes_upstream(self):
        with patch.object(proxy.subprocess, 'run') as run, local_handler() as port:
            for body, expected in ((b'not-hex\r\n', 400), (f'{proxy.MAX_BODY + 1:x}\r\n'.encode(), 413)):
                conn = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
                conn.request('PUT', '/api/test', body=body, headers={'Transfer-Encoding': 'chunked'})
                response = conn.getresponse()
                self.assertEqual(response.status, expected)
                response.read()
                conn.close()
            run.assert_not_called()

    def test_startup_still_rejects_external_network(self):
        outputs = [b'[{"NetworkSettings":{"Networks":{"qa-net":{}}}}]', b'[{"Internal":false}]']
        with patch('sys.argv', ['proxy', '--backend', 'wearable-compatible-qa-test-backend-http']), \
                patch.object(proxy.subprocess, 'check_output', side_effect=outputs), \
                patch.object(proxy.http.server, 'ThreadingHTTPServer') as server:
            with self.assertRaises(AssertionError):
                proxy.main()
            server.assert_not_called()


if __name__ == '__main__':
    unittest.main()
