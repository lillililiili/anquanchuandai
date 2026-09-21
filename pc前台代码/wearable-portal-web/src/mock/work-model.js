// Source works and local monitoring are separate. Never mutate source permits.
export function workSection(d, section) {
  if (d.config.module !== 'works' || d.config.mode === 'normal') return section
  const state = { forbidden: 'FORBIDDEN', failure: 'UNAVAILABLE', 'not-integrated': 'NOT_INTEGRATED' }[d.config.mode]
  return { state, data: null, reasonCode: state === 'FORBIDDEN' ? 'SECTION_FORBIDDEN' : 'SOURCE_' + state }
}
export function seedMonitoring(d) {
  d.relations.monitoring = d.entities.works.map((w, index) => {
    w.sourceStatus = index % 3 === 0 ? 'PLANNED' : index % 3 === 1 ? 'EXECUTING' : 'UNKNOWN'
    w.sourcePermit = '来源许可未知；本地监护不代表工作许可'
    return { workId: w.workId, siteId: w.siteId, state: 'PENDING', version: 1, supervisorId: null,
      personIds: d.entities.people.filter(p => p.siteId === w.siteId && p.works.data?.some(x => x.workId === w.workId)).map(p => p.personId), checks: [], timeline: [] }
  })
  d.relations.monitorOperations = []
  return d
}
export function workSummary(d, w) {
  const m = d.relations.monitoring?.find(m => m.workId === w.workId && m.siteId === w.siteId)
  return { ...w, monitorState: m?.state || 'PENDING', participantCount: new Set(m?.personIds || []).size,
    openEventCount: d.config.module === 'events' && d.config.mode !== 'normal' ? null : d.entities.events.filter(e => e.siteId === w.siteId && e.workId === w.workId && e.handlingStatus === 'UNHANDLED').length,
    localSupervisorId: m?.supervisorId || null, localSupervisorName: d.entities.people.find(p => p.siteId === w.siteId && p.personId === m?.supervisorId)?.name || null }
}
