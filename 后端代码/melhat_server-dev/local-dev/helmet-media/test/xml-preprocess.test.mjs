import test from 'node:test';
import assert from 'node:assert/strict';
import { MediaService } from '../service.mjs';

// FS v1.10.12 switch_xml.c:1361,1380-1382 reads lines and drops any containing <?.
// This is the parser used by mod_xml_curl for both directory and dialplan responses.
const retainedByFreeSwitch = xml => xml.split(/\r?\n/).filter(line => !line.includes('<?')).join('\n');
const service = () => new MediaService({ sipHost: 'fixture.invalid' }, { store: { data: {
  accounts: { fixture: { sipId: 'fixture', password: 'synthetic-password', kind: 'operator', roomId: 'room1' } },
  calls: { call1: { callId: 'call1', roomId: 'room1', status: 'dialing' } },
}, save() {} } });

test('directory remains a complete document after FreeSWITCH removes the declaration line', () => {
  const xml = service().directory(new URLSearchParams({ section: 'directory', user: 'fixture', domain: 'fixture.invalid' }));
  assert.match(retainedByFreeSwitch(xml), /^<document type="freeswitch\/xml">.*<section name="directory">.*<user id="fixture">.*<\/document>$/s);
  assert.match(retainedByFreeSwitch(xml), /<param name="password" value="synthetic-password"\/>/);
  assert.equal(retainedByFreeSwitch(xml.replace('?>\n', '?>')), '');
});

test('authorized dialplan survives FreeSWITCH declaration preprocessing', () => {
  const xml = service().directory(new URLSearchParams({ section: 'dialplan', variable_sip_auth_username: 'fixture', 'Caller-Destination-Number': 'room1' }));
  assert.match(retainedByFreeSwitch(xml), /^<document .*<section name="dialplan">.*<action application="conference".*<\/document>$/s);
});

test('denied directory and dialplan preserve an explicit not-found document', () => {
  for (const input of [{ section: 'directory', user: 'absent' }, { section: 'dialplan', variable_sip_auth_username: 'fixture', 'Caller-Destination-Number': 'wrong-room' }, { section: 'unknown' }]) {
    const xml = service().directory(new URLSearchParams(input));
    assert.match(retainedByFreeSwitch(xml), /^<document .*<result status="not found"\/>.*<\/document>$/s);
    assert.doesNotMatch(xml, /synthetic-password|application="conference"/);
  }
});
