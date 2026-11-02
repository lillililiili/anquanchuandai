"""Generate the push-only OpenAPI and synthetic fixtures from the existing V2 item schemas."""
from pathlib import Path
import base64
import hashlib
import hmac
import json

ROOT = Path(__file__).resolve().parent
QUERY = ROOT.parent / 'fuda-api-contract'
source = json.loads((QUERY / 'openapi.json').read_text(encoding='utf-8'))
schemas = {}


def include(name):
    if name in schemas:
        return
    schemas[name] = source['components']['schemas'][name]

    def visit(value):
        if isinstance(value, dict):
            if '$ref' in value:
                include(value['$ref'].split('/')[-1])
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
    visit(schemas[name])


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


examples = {}
for kind, schema, sample in [('POSITION', 'PositionItem', 'positions-success'),
                             ('STATUS', 'StatusItem', 'statuses-success'),
                             ('ALARM', 'AlarmItem', 'alarms-success')]:
    include(schema)
    props = {
        'schemaVersion': {'type': 'string', 'const': '1.0'},
        'eventId': {'type': 'string', 'pattern': r'^FP-[0-9a-f]{64}$', 'description': 'Stable delivery ID. Deduplicate before confirming receipt.'},
        'eventType': {'type': 'string', 'const': kind},
        'trigger': {'type': 'string', 'enum': ['REPORT', 'ONLINE', 'OFFLINE'] if kind == 'STATUS' else ['ALARM' if kind == 'ALARM' else 'REPORT']},
        'occurredAt': {'type': ['string', 'null'], 'format': 'date-time', 'description': 'Original observation time, not HTTP arrival time.'},
        'createdAt': {'type': 'string', 'format': 'date-time'},
        'data': {'$ref': '#/components/schemas/' + schema},
    }
    schemas[kind + 'Event'] = {'type': 'object', 'additionalProperties': False, 'required': list(props), 'properties': props}
    data = json.loads((QUERY / 'examples' / (sample + '.json')).read_text(encoding='utf-8'))['data']['items'][0]
    envelope = {'schemaVersion': '1.0', 'eventId': 'FP-' + hashlib.sha256(('synthetic:' + kind).encode()).hexdigest(),
                'eventType': kind, 'trigger': 'ALARM' if kind == 'ALARM' else 'REPORT',
                'occurredAt': '2026-10-27T07:59:55.000Z', 'createdAt': '2026-10-27T08:00:00.000Z', 'data': data}
    write(ROOT / 'examples' / (kind.lower() + '.json'), envelope)
    examples[kind] = {'summary': 'Synthetic ' + kind + ' event; not a real device', 'value': envelope}

headers = [('X-App-Id', {'type': 'string', 'pattern': r'^[A-Za-z0-9_-]{1,64}$'}),
           ('X-Timestamp', {'type': 'string', 'pattern': r'^[0-9]{1,12}$'}),
           ('X-Nonce', {'type': 'string', 'format': 'uuid'})]
spec = {
    'openapi': '3.1.0',
    'info': {'title': '福大穿戴数据推送接收协议（待联调确认）', 'version': '1.0.0',
             'description': 'Receiver contract proposal. Independent push credentials; existing V2 query APIs remain available. See README.md for exact HMAC canonical text, retries and timestamp semantics.'},
    'servers': [{'url': 'https://receiver.example.invalid', 'description': 'Placeholder only; supplied by Fuda before enabling'}],
    'paths': {'/receive': {'post': {
        'summary': '接收一条位置、状态或报警事件', 'operationId': 'receiveWearablePush',
        'parameters': [{'in': 'header', 'name': name, 'required': True, 'schema': schema} for name, schema in headers],
        'security': [{'HmacSignature': []}],
        'requestBody': {'required': True, 'content': {'application/json': {
            'schema': {'oneOf': [{'$ref': '#/components/schemas/' + kind + 'Event'} for kind in examples]}, 'examples': examples}}},
        'responses': {'200': {'description': 'Only integer code=0 after durable save (or durable duplicate) is successful.',
                              'content': {'application/json': {'schema': {'type': 'object', 'required': ['code'], 'properties': {'code': {'type': 'integer', 'const': 0}}}}}},
                      'default': {'description': 'Not confirmed. Sender retains the same eventId and retries with a fresh timestamp and nonce.'}},
    }}},
    'components': {'schemas': schemas, 'securitySchemes': {'HmacSignature': {'type': 'apiKey', 'in': 'header', 'name': 'X-Signature',
                    'description': 'Lowercase HMAC-SHA256 hex of POST, actual raw path, X-App-Id, X-Timestamp, X-Nonce, body SHA256 joined with LF; no trailing LF. Decode the 32-byte Base64 secret first.'}}},
}
write(ROOT / 'openapi.json', spec)
body = json.dumps(examples['STATUS']['value'], ensure_ascii=False, separators=(',', ':'))
canonical = '\n'.join(['POST', '/receive', 'push-example', '1791024000', '00000000-0000-4000-8000-000000000001', hashlib.sha256(body.encode()).hexdigest()])
key = bytes(range(32))
write(ROOT / 'examples' / 'signature-vector.json', {'purpose': 'PUBLIC TEST VECTOR ONLY. Never use this key in deployment.',
    'secretBase64': base64.b64encode(key).decode(), 'bodyText': body, 'canonicalText': canonical,
    'signature': hmac.new(key, canonical.encode(), hashlib.sha256).hexdigest()})
print('Generated push OpenAPI, 3 synthetic events and one public signature vector.')
