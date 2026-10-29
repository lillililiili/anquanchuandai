"""Read-only HTTP acceptance against an explicitly prepared loopback staging gateway.

No database writes, device commands, service startup or schema changes. Nonces are
necessarily claimed by the real API. Reports contain counts/check names only.
Credentials: --credentials-json with {"appId":...,"secretBase64":...}, or private
environment FUDA_VERIFY_APP_ID/FUDA_VERIFY_SECRET_BASE64. --env-file may supply
these two KEY=VALUE variables without executing shell expressions.
"""
import argparse
import base64
import datetime as dt
import hashlib
import hmac
import ipaddress
import json
import math
import os
from pathlib import Path
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


PREFIX = '/openapi/wearables/v2/'
ROUTES = {name: PREFIX + name + '/query' for name in ('positions', 'statuses', 'alarms')}
DEFAULT_DEVICES = [
    {'deviceType': 'HELMET', 'deviceId': '866652021714127'},
    {'deviceType': 'SAFETY_BELT', 'deviceId': '866652023095053'},
]
ALARM_TYPES = {'SOS', 'HELMET_REMOVED', 'AREA_EXIT', 'RESTRICTED_AREA_ENTRY',
    'TEMPERATURE_HIGH', 'FALL_OR_IMPACT', 'FALL', 'IMPACT', 'IMMOBILITY',
    'LOW_BATTERY', 'ELECTRIC_PROXIMITY', 'HEIGHT_EXCEEDED', 'BOTH_HOOKS_DETACHED',
    'SINGLE_HOOK_DETACHED', 'LOW_ANCHOR', 'BEACON_ENTER', 'BEACON_EXIT',
    'BODY_TEMPERATURE_HIGH', 'HEART_RATE_ABNORMAL', 'BLOOD_PRESSURE_ABNORMAL', 'UNKNOWN'}
VALIDITY = {'VALID', 'STALE', 'UNKNOWN', 'UNSUPPORTED'}
STAMP = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')


class VerificationFailure(Exception):
    """Controlled public diagnostic; never includes response body or credentials."""


def need(condition, message):
    if not condition:
        raise VerificationFailure(message)


def encoded(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'), sort_keys=True).encode('utf-8')


def fingerprint(value):
    return hashlib.sha256(encoded(value)).hexdigest()


def loopback_origin(value):
    parsed = urllib.parse.urlsplit(value)
    try:
        host = ipaddress.ip_address(parsed.hostname or '')
        port = parsed.port
    except ValueError:
        raise VerificationFailure('Target must be a literal loopback IP and valid port') from None
    need(parsed.scheme in ('http', 'https') and host.is_loopback, 'Only loopback HTTP(S) targets are allowed')
    need(not parsed.username and not parsed.password and not parsed.query and not parsed.fragment
        and parsed.path in ('', '/'), 'Target must be an origin without credentials, path or query')
    need(port is not None and 1024 <= port <= 65535, 'An explicit non-privileged gateway port is required')
    # Prevent accidental targeting of the daily backend or device ingress.
    need(port not in (18084, 18086, 18087, 18088), 'Daily backend/device ports are prohibited')
    return value.rstrip('/')


def private_json(path):
    file = Path(path)
    need(file.is_file() and not file.is_symlink(), 'Private JSON file must be a regular file')
    if os.name == 'posix':
        need(file.stat().st_mode & 0o077 == 0, 'Private JSON file requires mode 0600')
    need(file.stat().st_size <= 16 * 1024 * 1024, 'Private JSON file exceeds size bound')
    try:
        return json.loads(file.read_text(encoding='utf-8-sig'))
    except (OSError, ValueError):
        raise VerificationFailure('Private JSON file could not be decoded') from None


def credentials(args):
    values = dict(os.environ)
    if args.env_file:
        file = Path(args.env_file)
        if os.name == 'posix':
            need(file.stat().st_mode & 0o077 == 0, 'Private env file requires mode 0600')
        for line in file.read_text(encoding='utf-8-sig').splitlines():
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            key, separator, value = line.partition('=')
            need(bool(separator), 'Env file must contain KEY=VALUE lines')
            if key.strip() in ('FUDA_VERIFY_APP_ID', 'FUDA_VERIFY_SECRET_BASE64'):
                values[key.strip()] = value.strip().strip('\"\'')
    app = values.get('FUDA_VERIFY_APP_ID', '')
    secret = values.get('FUDA_VERIFY_SECRET_BASE64', '')
    if args.credentials_json:
        config = private_json(args.credentials_json)
        need(isinstance(config, dict), 'Credential JSON must be an object')
        app, secret = config.get('appId'), config.get('secretBase64')
    need(isinstance(app, str) and re.fullmatch(r'[A-Za-z0-9_-]{1,64}', app), 'App ID is missing or invalid')
    try:
        key = base64.b64decode(secret, validate=True)
    except (ValueError, TypeError):
        raise VerificationFailure('Secret must be Base64 encoding of exactly 32 bytes') from None
    need(len(key) == 32, 'Secret must decode to exactly 32 bytes')
    need(key != bytes(range(32)), 'Public example secret is prohibited for running acceptance')
    return app, key


def device_references(args):
    devices = private_json(args.devices_json) if args.devices_json else DEFAULT_DEVICES
    need(isinstance(devices, list) and 1 <= len(devices) <= 100, 'Device list must contain 1 to 100 references')
    seen = set()
    for ref in devices:
        need(isinstance(ref, dict) and set(ref) == {'deviceType', 'deviceId'}, 'Invalid device reference structure')
        need(ref['deviceType'] in ('HELMET', 'SAFETY_BELT') and isinstance(ref['deviceId'], str)
            and re.fullmatch(r'[A-Za-z0-9._-]{1,64}', ref['deviceId']), 'Invalid device type or number')
        key = (ref['deviceType'], ref['deviceId'])
        need(key not in seen, 'Duplicate device reference')
        seen.add(key)
    return devices


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Client:
    def __init__(self, origin, app, key, timeout=30):
        self.origin, self.app, self.key, self.timeout = loopback_origin(origin), app, key, timeout
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def request(self, kind, payload, *, raw=None, nonce=None, timestamp=None, bad_signature=False):
        body = encoded(payload) if raw is None else raw
        path = ROUTES[kind]
        timestamp = str(int(time.time()) if timestamp is None else timestamp)
        nonce = nonce or str(uuid.uuid4())
        text = '\n'.join(('POST', path, self.app, timestamp, nonce, hashlib.sha256(body).hexdigest()))
        signature = hmac.new(self.key, text.encode('utf-8'), hashlib.sha256).hexdigest()
        if bad_signature:
            signature = ('1' if signature[0] == '0' else '0') + signature[1:]
        headers = {'Content-Type': 'application/json; charset=utf-8', 'X-App-Id': self.app,
            'X-Timestamp': timestamp, 'X-Nonce': nonce, 'X-Signature': signature}
        return urllib.request.Request(self.origin + path, data=body, headers=headers, method='POST')

    def send(self, request):
        try:
            try:
                response = self.opener.open(request, timeout=self.timeout)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                data = response.read(8 * 1024 * 1024 + 1)
                need(len(data) <= 8 * 1024 * 1024, 'Response exceeds 8 MiB limit')
                need('application/json' in response.headers.get('Content-Type', '').lower(), 'Response is not JSON')
                try:
                    decoded = json.loads(data)
                except (ValueError, UnicodeError):
                    raise VerificationFailure('Response JSON is invalid') from None
                return response.status, decoded
        except (urllib.error.URLError, TimeoutError, OSError):
            raise VerificationFailure('HTTP transport failed; inspect private service logs') from None

    def call(self, kind, payload, **options):
        return self.send(self.request(kind, payload, **options))


def timestamp(value, nullable=False):
    need(value is None and nullable or isinstance(value, str) and STAMP.fullmatch(value), 'Timestamp format mismatch')
    if value is not None:
        try:
            # Fixed UTC milliseconds are already enforced above; strptime also works
            # on the existing server's Python 3.6 (fromisoformat requires 3.7).
            dt.datetime.strptime(value, '%Y-%m-%dT%H:%M:%S.%fZ')
        except ValueError:
            raise VerificationFailure('Timestamp calendar value is invalid') from None


def number(value, minimum=None, maximum=None, nullable=False):
    if value is None and nullable:
        return
    need(type(value) in (int, float) and math.isfinite(value), 'Measurement must be a finite number or explicit null')
    need(minimum is None or value >= minimum, 'Measurement below allowed bound')
    need(maximum is None or value <= maximum, 'Measurement above allowed bound')


def envelope(result, http=200, code=0):
    status, body = result
    need(status == http, 'Unexpected HTTP status: expected %s, received %s' % (http, status))
    need(isinstance(body, dict) and {'code', 'message', 'requestId', 'serverTime', 'data'} <= set(body), 'Response envelope fields missing')
    need(type(body['code']) is int and body['code'] == code, 'Unexpected application code: expected %s' % code)
    try:
        uuid.UUID(body['requestId'])
    except (TypeError, ValueError, AttributeError):
        raise VerificationFailure('requestId must be a UUID') from None
    timestamp(body['serverTime'])
    if code:
        need(body['data'] is None, 'Error response must not include partial data')
    else:
        need(isinstance(body['data'], dict) and isinstance(body['data'].get('items'), list), 'Successful response requires data.items')
    return body['data']


def common(item, scope):
    need(isinstance(item, dict) and {'sourcePlatform', 'deviceType', 'deviceId', 'deviceModel'} <= set(item), 'Device common fields missing')
    need(isinstance(item['sourcePlatform'], str) and item['sourcePlatform'], 'sourcePlatform is missing')
    need((item['deviceType'], item['deviceId']) in scope, 'Response contains an out-of-scope device')
    need(item['deviceModel'] is None or isinstance(item['deviceModel'], str), 'deviceModel must preserve explicit null or string')


def position(value):
    if value is None:
        return
    required = {'longitude', 'latitude', 'coordinateSystem', 'altitude', 'relativeHeight', 'heightReference',
        'speed', 'direction', 'positionTime', 'timeSource', 'positionMethod', 'historical'}
    need(isinstance(value, dict) and required <= set(value), 'Position fields are missing')
    number(value['longitude'], -180, 180)
    number(value['latitude'], -90, 90)
    need(value['longitude'] != 0 or value['latitude'] != 0, 'Placeholder zero position was exported')
    need(value['coordinateSystem'] in ('WGS84', 'GCJ02'), 'Unknown coordinate reference was exported as a position')
    timestamp(value['positionTime'])
    for name in ('altitude', 'relativeHeight', 'speed', 'direction'):
        number(value[name], nullable=True)
    need(value['speed'] is None or value['speed'] >= 0, 'Negative speed')
    need(value['direction'] is None or 0 <= value['direction'] < 360, 'Invalid direction')
    need(value['timeSource'] in ('DEVICE', 'PLATFORM') and type(value['historical']) is bool, 'Invalid position provenance')


class Acceptance:
    def __init__(self, client, devices, *, page_size=100, max_pages=100, expect_offline=True, min_history=1):
        self.client, self.devices = client, devices
        self.scope = {(r['deviceType'], r['deviceId']) for r in devices}
        self.page_size, self.max_pages, self.expect_offline = page_size, max_pages, expect_offline
        self.min_history = min_history
        self.checks, self.observations = [], {}
        self.final_cursor, self.events = None, {}

    def check(self, name, action):
        try:
            action()
            self.checks.append({'name': name, 'status': 'PASS'})
            return True
        except VerificationFailure as error:
            self.checks.append({'name': name, 'status': 'FAIL', 'reason': str(error)})
        except Exception as error:
            self.checks.append({'name': name, 'status': 'FAIL', 'reason': 'Unexpected verifier error: ' + type(error).__name__})
        return False

    def ordered(self, data):
        items = data['items']
        need(len(items) == len(self.devices), 'Response did not retain every requested device')
        for item, ref in zip(items, self.devices):
            common(item, self.scope)
            need(item['deviceType'] == ref['deviceType'] and item['deviceId'] == ref['deviceId'], 'Device response order mismatch')
        return items

    def positions(self, raw=None):
        items = self.ordered(envelope(self.client.call('positions', {'devices': self.devices}, raw=raw)))
        for item in items:
            need('position' in item and item.get('validity') in ('VALID', 'STALE', 'UNKNOWN'), 'Position validity missing')
            position(item['position'])
            if item['position'] is None:
                need(item['validity'] == 'UNKNOWN', 'Missing position must be UNKNOWN')
            elif self.expect_offline:
                need(item['validity'] != 'VALID', 'Isolated offline staging returned a currently VALID position')
        self.observations['positionCounts'] = {v: sum(i['validity'] == v for i in items) for v in ('VALID', 'STALE', 'UNKNOWN')}

    def statuses(self):
        items = self.ordered(envelope(self.client.call('statuses', {'devices': self.devices})))
        for item in items:
            need(item.get('onlineStatus') in ('ONLINE', 'OFFLINE'), 'Online status is invalid')
            timestamp(item.get('lastSeenAt'), True)
            for field in ('offlineTimeoutSeconds', 'telemetryMaxAgeSeconds'):
                need(type(item.get(field)) is int and item[field] > 0, 'Freshness timeout must be a positive integer')
            if self.expect_offline:
                need(item['onlineStatus'] == 'OFFLINE', 'Staging unexpectedly reports a real device ONLINE')
            for group in ('battery', 'network', 'wear', 'hookA', 'hookB'):
                value = item.get(group)
                need(isinstance(value, dict) and {'observedAt', 'validity'} <= set(value), 'Observation object fields missing')
                timestamp(value['observedAt'], True)
                need(value['validity'] in VALIDITY, 'Observation validity is invalid')
                if item['onlineStatus'] == 'OFFLINE':
                    need(value['validity'] != 'VALID', 'Offline observation must not be VALID')
            battery, network, wear = item['battery'], item['network'], item['wear']
            need({'percent', 'voltageMv'} <= set(battery), 'Battery null keys missing')
            number(battery['percent'], 0, 100, True)
            number(battery['voltageMv'], 0, nullable=True)
            if battery['percent'] is None:
                need(battery['validity'] == 'UNKNOWN', 'Unknown battery value must not imply a valid reading')
            need({'type', 'signalLevel'} <= set(network), 'Network null keys missing')
            number(network['signalLevel'], 0, 5, True)
            if network['signalLevel'] is None:
                need(network['validity'] == 'UNKNOWN', 'Unknown signal must not imply a valid reading')
            need(wear.get('status') in ('UNKNOWN', 'NOT_WORN', 'WORN', 'UNSUPPORTED'), 'Wear enum is invalid')
            for group in ('hookA', 'hookB'):
                hook = item[group]
                need(hook.get('status') in ('UNKNOWN', 'ATTACHED', 'DETACHED', 'UNSUPPORTED'), 'Hook enum is invalid')
                if item['deviceType'] == 'HELMET':
                    need(hook['status'] == hook['validity'] == 'UNSUPPORTED', 'Helmet must not report belt hook state')
        self.observations['onlineCounts'] = {v: sum(i['onlineStatus'] == v for i in items) for v in ('ONLINE', 'OFFLINE')}

    def alarm_page(self, cursor):
        data = envelope(self.client.call('alarms', {'cursor': cursor, 'limit': self.page_size}))
        need(isinstance(data.get('nextCursor'), str) and 1 <= len(data['nextCursor']) <= 512, 'Alarm cursor is missing')
        need(type(data.get('hasMore')) is bool, 'hasMore must be boolean')
        need(len(data['items']) <= self.page_size and (not data['hasMore'] or data['items']), 'Alarm pagination contract violated')
        page = {}
        for item in data['items']:
            common(item, self.scope)
            need(isinstance(item.get('eventId'), str) and 1 <= len(item['eventId']) <= 128, 'Stable event ID is missing')
            for field in ('occurredAt', 'receivedAt'):
                need(field in item, 'Alarm time null key missing')
                timestamp(item[field], True)
            need(item.get('alarmType') in ALARM_TYPES and item.get('alarmOrigin') in ('DEVICE', 'PLATFORM'), 'Alarm enum is invalid')
            need(isinstance(item.get('alarmContent'), str) and item['alarmContent'], 'Alarm content is missing')
            for field in ('rawAlarmType', 'rawAlarmName'):
                need(field in item and (item[field] is None or isinstance(item[field], str)), 'Raw alarm field null/type mismatch')
            need({'positionSource', 'position', 'positionAgeSeconds'} <= set(item), 'Alarm location fields missing')
            if item['positionSource'] == 'NONE':
                need(item['position'] is None and item['positionAgeSeconds'] is None, 'NONE alarm location must preserve null values')
            else:
                need(item['positionSource'] in ('EVENT', 'LAST_KNOWN') and item['position'] is not None, 'Invalid alarm location provenance')
                position(item['position'])
                number(item['positionAgeSeconds'], 0, 300)
            identity = fingerprint([item['sourcePlatform'], item['eventId']])
            need(identity not in page, 'Duplicate event ID within one page')
            page[identity] = fingerprint(item)
        return data, page

    def history(self):
        first, first_events = self.alarm_page(None)
        repeat, repeated_events = self.alarm_page(None)
        need(list(repeated_events)[:len(first_events)] == list(first_events), 'Repeated first page changed committed event ordering')
        need(all(repeated_events.get(k) == v for k, v in first_events.items()), 'An immutable alarm changed between repeated pulls')
        # Reusing the same identity-keyed local store must not duplicate already saved alarms.
        deduplicated = dict(first_events)
        for key in first_events:
            deduplicated[key] = repeated_events[key]
        need(len(deduplicated) == len(first_events), 'Receiver deduplication check failed')
        self.observations['firstPageRepeatedEvents'] = len(first_events)
        self.observations['firstPageCursorStable'] = first['nextCursor'] == repeat['nextCursor']
        all_events, data, page, count = {}, first, first_events, 0
        while True:
            count += 1
            need(count <= self.max_pages, 'History exceeds bounded pagination; increase --max-pages before claiming completeness')
            need(not (set(all_events) & set(page)), 'Cursor continuation repeated a previously committed event')
            all_events.update(page)
            cursor = data['nextCursor']
            data, page = self.alarm_page(cursor)
            if not data['hasMore'] and not page:
                self.final_cursor, self.events = data['nextCursor'], all_events
                break
            need(data['nextCursor'] != cursor, 'Nonempty alarm continuation did not advance its cursor')
        self.observations.update({'alarmPagesSaved': count, 'alarmCount': len(all_events),
            'alarmSetDigest': fingerprint(all_events), 'terminalEmptyPageVerified': True,
            'nonemptyAlarmRepeatExercised': bool(first_events)})
        need(len(all_events) >= self.min_history, 'Insufficient retained alarm evidence for the expected historical acceptance')
        need(not self.min_history or first_events, 'First page had no alarm evidence; rerun after initial ingestion settles')

    def resumed(self, checkpoint, min_new):
        need(isinstance(checkpoint, dict) and checkpoint.get('version') == 1, 'Unsupported checkpoint structure/version')
        need(checkpoint.get('applicationHash') == fingerprint(self.client.app)
            and checkpoint.get('deviceScopeHash') == fingerprint(self.devices), 'Checkpoint belongs to different application or devices')
        old = checkpoint.get('events')
        need(isinstance(old, dict) and isinstance(checkpoint.get('cursor'), str), 'Checkpoint structure is invalid')
        need(all(self.events.get(k) == v for k, v in old.items()), 'Previously saved alarms are missing or changed after recovery')
        cursor, resumed_events, pages = checkpoint['cursor'], {}, 0
        while True:
            pages += 1
            need(pages <= self.max_pages, 'Resume exceeds bounded pagination')
            data, page = self.alarm_page(cursor)
            need(not (set(resumed_events) & set(page)) and not (set(old) & set(page)), 'Resume returned an old or duplicate event')
            resumed_events.update(page)
            if not data['hasMore']:
                break
            need(data['nextCursor'] != cursor, 'Resume cursor did not advance')
            cursor = data['nextCursor']
        expected = {k: v for k, v in self.events.items() if k not in old}
        need(resumed_events == expected, 'Resume and current full-history results differ; inspect data or retry after pending reports drain')
        need(len(expected) >= min_new, 'Fewer new alarms than the explicitly expected minimum')
        self.observations['resumedNewAlarms'] = len(expected)

    def run(self, checkpoint=None, min_new=0):
        payload = {'devices': self.devices}
        self.check('positions_signed_query', self.positions)
        self.check('statuses_signed_query_and_unknown_offline_rules', self.statuses)
        for name, newline in [('LF', '\n'), ('CRLF', '\r\n')]:
            raw = (json.dumps(payload, ensure_ascii=False, indent=2).replace('\n', newline) + newline).encode('utf-8')
            self.check('formatted_' + name + '_signature', lambda raw=raw: self.positions(raw))
        self.check('incorrect_signature_rejected', lambda: envelope(self.client.call('positions', payload, bad_signature=True), 401, 40101))
        self.check('expired_timestamp_rejected', lambda: envelope(self.client.call('positions', payload, timestamp=int(time.time()) - 601), 401, 40102))
        def replay():
            request = self.client.request('statuses', payload)
            envelope(self.client.send(request))
            envelope(self.client.send(request), 409, 40902)
        self.check('real_nonce_store_replay_rejected', replay)
        denied = {'deviceType': 'HELMET', 'deviceId': 'FUDA-UNAUTHORIZED-' + uuid.uuid4().hex[:16]}
        self.check('unauthorized_batch_rejected_without_partial_data', lambda: envelope(
            self.client.call('positions', {'devices': [self.devices[0], denied]}), 403, 40301))
        self.check('invalid_cursor_rejected', lambda: envelope(self.client.call('alarms', {'cursor': 'not-a-valid-cursor'}), 400, 40002))
        self.check('duplicate_json_fields_rejected', lambda: envelope(self.client.call('alarms', {}, raw=b'{"cursor":null,"cursor":null}'), 400, 40001))
        history_ok = self.check('alarm_history_repeat_dedup_and_continuation', self.history)
        if checkpoint is not None:
            if history_ok:
                self.check('saved_cursor_recovery_and_new_alarm_completeness', lambda: self.resumed(checkpoint, min_new))
            else:
                self.checks.append({'name': 'saved_cursor_recovery_and_new_alarm_completeness', 'status': 'NOT_RUN', 'reason': 'History check failed'})
        return not any(c['status'] != 'PASS' for c in self.checks)

    def checkpoint(self):
        need(self.final_cursor is not None, 'A successful historical scan is required before saving a checkpoint')
        return {'version': 1, 'applicationHash': fingerprint(self.client.app), 'deviceScopeHash': fingerprint(self.devices),
            'cursor': self.final_cursor, 'events': self.events}


def write_private_new(path, value):
    file = Path(path)
    need(not file.exists(), 'Output already exists; use a new file to preserve previous evidence')
    file.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with os.fdopen(os.open(file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w', encoding='utf-8') as out:
        json.dump(value, out, ensure_ascii=False, indent=2)
        out.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url', default='http://127.0.0.1:18089')
    parser.add_argument('--credentials-json')
    parser.add_argument('--env-file')
    parser.add_argument('--devices-json', help='Private JSON array; defaults to the two currently approved real device numbers')
    parser.add_argument('--page-size', type=int, choices=range(1, 501), default=100, metavar='1..500')
    parser.add_argument('--max-pages', type=int, default=100)
    parser.add_argument('--timeout', type=int, default=30)
    parser.add_argument('--allow-online', action='store_true', help='Only for separately authorized live acceptance; default staging must be OFFLINE')
    parser.add_argument('--checkpoint-in')
    parser.add_argument('--checkpoint-out')
    parser.add_argument('--min-new-alarms', type=int, default=0)
    parser.add_argument('--min-historical-alarms', type=int, default=1,
        help='Default requires actual retained alarms; 0 is an explicit empty-history smoke test only')
    parser.add_argument('--report-out')
    args = parser.parse_args()
    report = {'suite': 'fuda-staging-http', 'time': dt.datetime.now(dt.timezone.utc).isoformat(),
        'mode': 'READ_ONLY_HTTP_QUERIES', 'status': 'FAIL',
        'limitations': ['No real device or video command is issued.',
            'Offline staging does not prove live device ingress or current measurements.',
            'A saved-cursor check only proves restart recovery when the operator actually restarts services between runs.',
            'Live MySQL concurrent writes and real video interoperability need separate acceptance.']}
    try:
        need(1 <= args.max_pages <= 10000 and 1 <= args.timeout <= 120 and args.min_new_alarms >= 0
            and args.min_historical_alarms >= 0, 'Invalid verification bounds')
        origin = loopback_origin(args.base_url)
        app, key = credentials(args)
        devices = device_references(args)
        checkpoint = private_json(args.checkpoint_in) if args.checkpoint_in else None
        need(args.min_new_alarms == 0 or checkpoint is not None, '--min-new-alarms requires a previous private checkpoint')
        verifier = Acceptance(Client(origin, app, key, args.timeout), devices,
            page_size=args.page_size, max_pages=args.max_pages, expect_offline=not args.allow_online,
            min_history=args.min_historical_alarms)
        ok = verifier.run(checkpoint, args.min_new_alarms)
        report.update({'status': 'PASS' if ok else 'FAIL', 'checks': verifier.checks,
            'observations': verifier.observations, 'requestedDeviceCount': len(devices),
            'passedChecks': sum(c['status'] == 'PASS' for c in verifier.checks), 'totalChecks': len(verifier.checks)})
        if ok and args.checkpoint_out:
            write_private_new(args.checkpoint_out, verifier.checkpoint())
            report['checkpointSaved'] = True
    except VerificationFailure as error:
        report['reason'] = str(error)
    except Exception as error:
        report['reason'] = 'Verifier configuration/IO failure: ' + type(error).__name__
    if args.report_out:
        try:
            write_private_new(args.report_out, report)
        except (OSError, VerificationFailure) as error:
            report['status'] = 'FAIL'
            report['reportWriteFailure'] = str(error) if isinstance(error, VerificationFailure) else type(error).__name__
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report['status'] == 'PASS' else 2


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    raise SystemExit(main())
