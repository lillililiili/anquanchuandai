import io
import unittest
import urllib.error
from unittest.mock import patch

import cloud_identity


class FakeOpener:
    def __init__(self, responses):
        self.responses = list(responses)
        self.requests = []

    def open(self, request, timeout):
        self.requests.append((request, timeout))
        result = self.responses.pop(0)
        if isinstance(result, Exception):
            raise result
        return io.BytesIO(result)


class IdentityTest(unittest.TestCase):
    def test_token_protected_metadata_succeeds_without_external_network(self):
        opener = FakeOpener([b'private-metadata-token', b'39.106.212.138'])
        self.assertEqual(cloud_identity.authorized_public_ip(opener), cloud_identity.EXPECTED)
        token, address = [item[0] for item in opener.requests]
        self.assertEqual(token.get_method(), 'PUT')
        self.assertEqual(token.get_header('X-aliyun-ecs-metadata-token-ttl-seconds'), '60')
        self.assertEqual(address.get_header('X-aliyun-ecs-metadata-token'), 'private-metadata-token')
        self.assertTrue(all(item[0].full_url.startswith(cloud_identity.METADATA) for item in opener.requests))

    def test_eip_supported_when_public_address_absent(self):
        opener = FakeOpener([b'token', b'', b'39.106.212.138'])
        self.assertEqual(cloud_identity.authorized_public_ip(opener), cloud_identity.EXPECTED)
        self.assertTrue(opener.requests[-1][0].full_url.endswith('/eipv4'))

    def test_wrong_instance_never_accepted_via_another_lookup(self):
        opener = FakeOpener([b'token', b'203.0.113.20', b'39.106.212.138'])
        with self.assertRaisesRegex(RuntimeError, 'does not match'):
            cloud_identity.authorized_public_ip(opener)
        self.assertEqual(len(opener.requests), 2)

    def test_timeout_is_clear_and_does_not_leak_token_or_disable_verification(self):
        opener = FakeOpener([TimeoutError('internal-error-sensitive')])
        with self.assertRaises(RuntimeError) as caught:
            cloud_identity.authorized_public_ip(opener)
        self.assertIn('Cannot read ECS metadata token', str(caught.exception))
        self.assertNotIn('internal-error-sensitive', str(caught.exception))
        self.assertEqual(len(opener.requests), 1)

    def test_invalid_or_missing_addresses_fail_closed(self):
        for value in (b'', b'<html>error</html>', b'39.106.212.138\n203.0.113.20'):
            with self.assertRaisesRegex(RuntimeError, 'Cannot verify'):
                cloud_identity.authorized_public_ip(FakeOpener([b'token', value, b'']))

    def test_metadata_uses_neither_proxy_nor_redirect(self):
        opener = FakeOpener([b'token', b'39.106.212.138'])
        with patch('cloud_identity.urllib.request.build_opener', return_value=opener) as build:
            cloud_identity.authorized_public_ip()
        proxy, redirect = build.call_args[0]
        self.assertEqual(proxy.proxies, {})
        self.assertIsNone(redirect.redirect_request(None, None, 302, '', {}, 'https://example.com'))


if __name__ == '__main__':
    unittest.main()
