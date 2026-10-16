export const navigationItems = [
  { id: 'overview', label: '综合总览' },
  { id: 'personnel', label: '人员与装备' },
  { id: 'works', label: '作业监护' },
  { id: 'video', label: '视频监看' },
  { id: 'dispatch', label: '调度通信' },
  { id: 'location', label: '定位与轨迹' },
  { id: 'alarms', label: '告警与核验' },
  { id: 'materials', label: '现场资料' },
  { id: 'statistics', label: '统计追溯' },
];

const owners = { person: 'personnel', work: 'works', single: 'video', tracks: 'location', fences: 'location', event: 'alarms', sos: 'dispatch' };
export const navigationOwner = (routeName) => owners[routeName] || routeName;

// Keep a contiguous visible prefix, using both sides before hiding a trailing
// suffix. Up to four entries stay left of the title; narrower layouts rebalance.
export function fitNavigation(widths, leftWidth, rightWidth, moreWidth, gap = 4) {
  const occupied = (list) => list.reduce((sum, value) => sum + value, 0) + Math.max(0, list.length - 1) * gap;
  for (let count = widths.length; count >= 0; count -= 1) {
    for (let leftCount = Math.min(4, count); leftCount >= 0; leftCount -= 1) {
      const left = widths.slice(0, leftCount);
      const right = widths.slice(leftCount, count);
      if (count < widths.length) right.push(moreWidth);
      if (occupied(left) <= leftWidth && occupied(right) <= rightWidth) return { visibleCount: count, leftCount };
    }
  }
  return { visibleCount: 0, leftCount: 0 };
}

export function pageFamily(routeName) {
  if (['overview','statistics'].includes(routeName)) return 'monitor';
  if (['person','work','event'].includes(routeName)) return 'detail';
  if (['video','single','dispatch','sos','location','tracks','fences','screen'].includes(routeName)) return 'sentinel';
  return 'list';
}
