import { reactive } from 'vue';
export const session = reactive({
  station: 'S1', person: 'QA-PERSON', work: 'QA-WORK', event: 'QA-SOS', media: '', fence: '', group: '',
  layout: '1+7', playing: true, volume: 0, rotation: false, recording: null, videoTick: 0,
  trackPlaying: false, trackIndex: 0, trackSpeed: 1, trackPoints: [], selectedMembers: ['QA-PERSON'],
  layers: { people: true, fences: true }, filters: {}, fenceDraft: null, fenceMode: 'select', fenceUndo: [],
  formDrafts: {}, mediaTab: 'all', personTab: '人员信息', statsTab: '综合', dispatchTab: 'people',
  sosConfirm: false, hidePerson: false, broadcastDraft: '', showPassword: false,
});
export function filtersOf(name) { return session.filters[name] || (session.filters[name] = {}); }
