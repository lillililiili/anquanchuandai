"""Read-only local API check; credentials and person data are never logged."""
import json
import os
import urllib.request
from pathlib import Path

base = 'http://127.0.0.1:18084'
headers = {'Content-Type': 'application/json', 'X-Site-Id': '1'}


def api(path, payload=None):
    req = urllib.request.Request(base + path, headers=headers,
        data=None if payload is None else json.dumps(payload).encode())
    with urllib.request.urlopen(req, timeout=20) as response:
        result = json.load(response)
    assert result.get('code') == 200, 'API request failed'
    return result


login = api('/login', {'username': os.environ['EVENT_VERIFY_USER'],
                       'password': os.environ['EVENT_VERIFY_PASSWORD']})
headers['Authorization'] = 'Bearer ' + login['token']
detail = api('/api/v1/events/167')['data']
assert detail['alarmCode'] == 'helmet.fence_exit'
assert detail['alarmName'] == '离开指定区域'
assert detail['alarmDescription'] == '离开指定区域'
rows = []
current = 1
while True:
    page = api(f'/api/v1/events?status=all&size=100&current={current}')['data']
    rows.extend(page['records'])
    if len(rows) >= page['total']:
        break
    assert page['records'], 'Unexpected empty page'
    current += 1
assert next(row for row in rows if row['id'] == '167')['alarmName'] == detail['alarmName']
samples = {}
for row in rows:
    code = row.get('alarmCode')
    if code and code not in samples:
        returned = api('/api/v1/events/' + row['id'])['data']
        for field in ('alarmCode', 'alarmName', 'alarmDescription'):
            assert row.get(field) == returned.get(field), field
        samples[code] = row.get('alarmName')
evidence = {'event167': {key: detail.get(key) for key in
    ('id', 'type', 'alarmCode', 'alarmName', 'alarmDescription', 'status', 'demo')},
    'checkedEventCount': len(rows), 'listDetailConsistent': True,
    'existingScenarioNames': samples}
Path(__file__).with_name('backend-api-evidence.json').write_text(
    json.dumps(evidence, ensure_ascii=False, indent=2), encoding='utf-8')
print('PASS: event #167 and', len(samples), 'existing scenario names match list/detail API')
