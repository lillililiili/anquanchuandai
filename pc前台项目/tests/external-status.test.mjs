import test from 'node:test';
import assert from 'node:assert/strict';
import { externalStatusPresentation } from '../src/lib/external-status.js';

test('an absent external source stays disconnected even after local verification or an orphaned success flag', () => {
  for (const externalStatus of [undefined, '', '未接入外部系统', '待回传', '摘要成功']) {
    assert.deepEqual(externalStatusPresentation({ externalStatus, status: '已核验', verification: { conclusion: '已处理' } }), { label: '未接入', color: 'muted' });
  }
  assert.deepEqual(externalStatusPresentation({ externalId: ' ', externalSource: 'UNKNOWN', externalStatus: '摘要成功' }), { label: '未接入', color: 'muted' });
});

test('a linked external record shows exactly its explicit status and never infers success from a missing or new status', () => {
  for (const externalStatus of [undefined, '', '   ']) {
    assert.deepEqual(externalStatusPresentation({ externalId: 'EX-1', externalStatus }), { label: '状态待确认', color: 'muted' });
  }
  for (const externalStatus of ['待回传', '处理中', '未接入外部系统', 'NEW_VENDOR_STATUS']) {
    assert.deepEqual(externalStatusPresentation({ externalRecordId: 123, externalStatus }), { label: externalStatus, color: 'muted' });
  }
});

test('success and failure colors require a source and an explicit matching external result', () => {
  assert.deepEqual(externalStatusPresentation({ externalId: 'EX-1', externalStatus: '摘要成功' }), { label: '摘要成功', color: 'green' });
  assert.deepEqual(externalStatusPresentation({ externalSource: 'verified-adapter', externalStatus: '回传失败' }), { label: '回传失败', color: 'red' });
  assert.deepEqual(externalStatusPresentation({ externalId: 'EX-1', externalStatus: '未成功' }), { label: '未成功', color: 'muted' });
});
