"""Read only the ECS public address using token-protected instance metadata.

Compatible with the cloud host's Python 3.6. No proxy, redirect, RAM role
credentials, or third-party IP lookup is involved.
"""
import ipaddress
import sys
import urllib.error
import urllib.request

EXPECTED = '39.106.212.138'
METADATA = 'http://100.100.100.200/latest/'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _read(opener, request, limit):
    with opener.open(request, timeout=4) as response:
        data = response.read(limit + 1)
        if len(data) > limit:
            raise ValueError('Unexpected metadata response size')
        return data.decode('ascii').strip()


def authorized_public_ip(opener=None):
    if opener is None:
        opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), NoRedirect())
    try:
        token = _read(opener, urllib.request.Request(
            METADATA + 'api/token', data=b'', method='PUT',
            headers={'X-aliyun-ecs-metadata-token-ttl-seconds': '60'}), 4096)
        if not token or '\n' in token or '\r' in token:
            raise ValueError('Invalid metadata token')
    except (OSError, ValueError, UnicodeError):
        raise RuntimeError('Cannot read ECS metadata token; check instance metadata access. No service configuration changed.') from None
    for field in ('public-ipv4', 'eipv4'):
        try:
            value = _read(opener, urllib.request.Request(
                METADATA + 'meta-data/' + field,
                headers={'X-aliyun-ecs-metadata-token': token}), 64)
            if not value:
                continue
            actual = str(ipaddress.IPv4Address(value))
        except (OSError, ValueError, UnicodeError):
            continue
        if actual != EXPECTED:
            raise RuntimeError('ECS public IP does not match authorized server ' + EXPECTED)
        return actual
    raise RuntimeError('Cannot verify ECS public IPv4 from metadata; refusing installation.')


if __name__ == '__main__':
    try:
        print(authorized_public_ip())
    except RuntimeError as error:
        sys.exit(str(error))
