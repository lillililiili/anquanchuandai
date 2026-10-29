import test from 'node:test';
import assert from 'node:assert/strict';
import { TEST_SITE, testSiteChoices, testSiteName } from '../../shared/test-site.mjs';

test('test site display preserves original IDs and cannot select another authorized site', () => {
  const stations = [{ id: 'S2', name: '另一厂站' }, { id: 'S1', name: '原始厂站', siteId: 'site-1' }];
  const before = JSON.stringify(stations);
  assert.deepEqual(testSiteChoices(stations, 'station'), [{ ...stations[1], name: '测试厂区' }]);
  assert.deepEqual(testSiteChoices([stations[0]], 'station'), []);
  assert.equal(testSiteName(stations[0]), '另一厂站');
  assert.equal(JSON.stringify(stations), before);
  assert.deepEqual(testSiteChoices(stations, 'station', false), stations);
});

test('a saved S2 selection cannot take the portal out of the fixed test site', async () => {
  const saved = JSON.stringify({ station: 'S2', fenceDraft: { station: 'S2', points: [[1, 2]] }, filters: { works: { workId: 'other-site' } }, formDrafts: { person: { station: 'S2' } } });
  globalThis.localStorage = { getItem: () => 'S1' };
  globalThis.sessionStorage = { getItem: () => saved, setItem: () => {} };
  try {
    const { session } = await import('../src/stores/session.js');
    assert.equal(session.station, TEST_SITE.stationId);
    assert.equal(session.fenceDraft, null);
    assert.deepEqual(session.filters, {});
    assert.deepEqual(session.formDrafts, {});
  } finally {
    delete globalThis.localStorage;
    delete globalThis.sessionStorage;
  }
});
