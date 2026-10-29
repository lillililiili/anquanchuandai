const text = value => typeof value === 'string' ? value.trim() : Array.isArray(value) ? value.filter(item => typeof item === 'string').join('、') : '';

export function workRisks(work) {
  return {
    riskFactors: text(work?.riskFactors) || text(work?.riskSummary) || text(work?.risks),
    measures: text(work?.safetyMeasures) || text(work?.measures),
  };
}

export function workTimeline(work, events, personName) {
  if (!work) return [];
  const recorded = Array.isArray(work.timeline) ? work.timeline.filter(entry => entry && typeof entry.time === 'string' && typeof entry.text === 'string') : [];
  return [
    ...recorded.map(entry => ({ time: entry.time, text: entry.text })),
    ...events.filter(event => event.workId === work.id).map(event => ({ time: `${event.date || ''} ${event.time || ''}`.trim(), text: `${personName(event.personId) || '未关联人员'}　${event.title}` })),
  ].sort((a, b) => a.time.localeCompare(b.time));
}
