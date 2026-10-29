import test from 'node:test';
import assert from 'node:assert/strict';
import { sipLogDiagnostic, sipRegistrationState } from '../src/lib/sip-diagnostics.js';

test('SIP wire diagnostics retain method/status but never identities, authorization, addresses or SDP', () => {
  const secret = 'should-never-be-in-console';
  const request = `Sending WebSocket message:\n\nREGISTER sip:${secret}@198.51.100.19 SIP/2.0\r\nAuthorization: Digest password="${secret}"\r\nCSeq: 1 REGISTER\r\n\r\nv=0\n${secret}\n`;
  const response = `Received WebSocket text message:\n\nSIP/2.0 401 ${secret}\r\nCSeq: 1 REGISTER\r\nWWW-Authenticate: Digest nonce="${secret}"\r\n\r\n`;
  assert.deepEqual(sipLogDiagnostic(request), { event:'wire',direction:'sent',method:'REGISTER' });
  assert.deepEqual(sipLogDiagnostic(response), { event:'wire',direction:'received',method:'REGISTER',status:401 });
  assert.equal(JSON.stringify([sipLogDiagnostic(request),sipLogDiagnostic(response)]).includes(secret), false);
  assert.equal(sipLogDiagnostic(`· authorizationPassword: ${secret}`), null);
  assert.equal(sipLogDiagnostic({password:secret}), null);
});

test('Only exact fixed SIP warning messages and known states are recorded', () => {
  assert.deepEqual(sipLogDiagnostic('Via sent-by in the response does not match UA Via host value. Dropping.'), {event:'response_via_mismatch'});
  assert.equal(sipLogDiagnostic('Via sent-by in the response does not match UA Via host value. Dropping. secret'), null);
  assert.deepEqual(sipLogDiagnostic('No Contact header pointing to us, dropping response'), {event:'register_contact_mismatch'});
  assert.equal(sipRegistrationState('Registered'), 'Registered');
  assert.equal(sipRegistrationState('secret@private'), 'unknown');
  assert.equal(sipLogDiagnostic('Received WebSocket text message:\n\nSIP/2.0 200 OK\r\nCSeq: 1 SECRET\r\n'), null);
});
