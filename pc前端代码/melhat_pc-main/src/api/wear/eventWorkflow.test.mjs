import { test } from 'node:test'
import assert from 'node:assert/strict'
import { canReviewVerification, verificationStepLabel, reviewActorHint } from './eventWorkflow.js'
const admin = { isPlatformAdmin: true, canReviewEvent: true, userId: '1', name: 'admin' }
const sos = { type: 'sos', source: 'helmet', severity: 'emergency', status: 'pending_review' }
test('device SOS administrator may approve own field report', () => {
  assert.equal(canReviewVerification(sos, admin, [{ action: 'handle', actor: 'admin' }]), true)
  assert.equal(canReviewVerification(sos, admin, []), false)
  assert.match(reviewActorHint(sos), /允许管理员审批自己/)
})
test('manual SOS requires a different administrator without field report', () => {
  const manual = { ...sos, source: 'manual_sos', reporterUserId: '1' }
  assert.equal(canReviewVerification(manual, admin), false)
  assert.equal(canReviewVerification({ ...manual, reporterUserId: '2' }, admin), true)
})
test('ordinary members and old reviewer-only users cannot approve', () => {
  for (const actor of [{ ...admin, isPlatformAdmin: false }, { ...admin, canReviewEvent: false }])
    assert.equal(canReviewVerification(sos, actor, [{ action: 'handle', actor: 'other' }]), false)
})
test('non-SOS emergency requires a different field reporter', () => {
  assert.equal(canReviewVerification({ ...sos, type: 'realtime' }, admin, [{ action: 'handle', actor: 'admin' }]), false)
  assert.equal(canReviewVerification({ ...sos, type: 'realtime' }, admin, [{ action: 'handle', actor: 'other' }]), true)
})
test('completed and unsubmitted events cannot be approved again', () => {
  for (const status of ['open', 'handling', 'verified', 'confirmed', 'closed'])
    assert.equal(canReviewVerification({ ...sos, status }, admin, [{ action: 'handle', actor: 'other' }]), false)
})
test('unknown history never implies verified or externally closed', () => {
  assert.equal(verificationStepLabel('unknown'), '历史结果待确认')
  assert.equal(verificationStepLabel(undefined), '未同步')
  assert.equal(verificationStepLabel('verified'), '已核验')
})
