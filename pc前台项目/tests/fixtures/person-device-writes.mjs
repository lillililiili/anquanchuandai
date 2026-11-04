import { fenceWriteIssue } from '../../src/views/fences/fence-policy.js';

// Used only by the 5194 fixture. Never swap in a production API or persistence
// adapter: the original store validates geometry, then this gate checks scope.
export function allowFixtureFenceCommit(before, after, scenario) {
  if (scenario !== 'fences') throw Error('隔离验收：当前场景不允许业务写入');
  const mutable = new Set(['fences','audit','seq','clock']);
  for (const key of new Set([...Object.keys(before), ...Object.keys(after)])) {
    if (!mutable.has(key) && JSON.stringify(before[key]) !== JSON.stringify(after[key])) throw Error('隔离验收：只允许围栏内存变更');
  }
  const label = after.audit.at(-1)?.text;
  if (!['保存电子围栏','启用围栏','停用围栏','归档围栏'].includes(label)) throw Error('隔离验收：未允许此操作');
  for (const fence of after.fences) {
    const original = before.fences.find(item => item.id === fence.id);
    if (JSON.stringify(original) === JSON.stringify(fence)) continue;
    const issue = fenceWriteIssue(fence, false);
    if (issue && !(fence.archived === true && fence.enabled === false && original
        && JSON.stringify(fence.points) === JSON.stringify(original.points))) throw Error(issue);
  }
  return label;
}
