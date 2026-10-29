import { reactive, watch } from "vue";
import { TEST_SITE_MODE, TEST_SITE } from '../../../shared/test-site.mjs';
import { DEMO_MODE } from '../lib/data-mode.js';

function defaults() {
  return {
    station: "S1",
    person: "P1",
    work: "GL-20260915-018",
    event: "RL-E-0915-001",
    media: "IMG-0915-001",
    fence: "F1",
    group: "G1",
    layout: "1+7",
    playing: true,
    volume: 50,
    rotation: false,
    recording: null,
    trackPlaying: false,
    trackIndex: 0,
    trackSpeed: 1,
    trackPoints: [],
    selectedMembers: ["P1", "P2", "P3"],
    layers: { people: true, fences: true },
    filters: {},
    fenceDraft: null,
    fenceMode: "select",
    fenceUndo: [],
    formDrafts: {},
    videoTick: 12,
    mediaTab: "all",
    personTab: "人员信息",
    statsTab: "综合",
    dispatchTab: "people",
    sosConfirm: false,
    hidePerson: false,
    broadcastDraft: "",
    showPassword: false,
  };
}

function load() {
  const state = defaults();
  try {
    const saved = JSON.parse(sessionStorage.getItem("rolling-view") || "null");
    if (saved && typeof saved === "object" && saved.viewVersion === 'wearable-person-v2') Object.assign(state, saved);
  } catch {
    /* 损坏的会话不阻止进入页面。 */
  }
  const restoredStation = state.station;
  state.station = localStorage.getItem("rolling-station") || state.station || "S1";
  if (TEST_SITE_MODE) {
    if (state.station !== TEST_SITE.stationId || restoredStation !== TEST_SITE.stationId) {
      state.fenceDraft = null;
      state.fenceUndo = [];
      state.filters = {};
      state.formDrafts = {};
      state.selectedMembers = [];
    }
    state.station = TEST_SITE.stationId;
  }
  state.recording = null;
  state.viewVersion = 'wearable-person-v2';
  if (!DEMO_MODE && !sessionStorage.getItem('rolling-view')?.includes('wearable-person-v2')) {
    for(const field of ['person','work','event','media','fence','group'])state[field]='';
    state.selectedMembers=[];state.filters={};state.formDrafts={};
  }
  state.trackPlaying = false;
  state.layers = { people: state.layers?.people !== false, fences: state.layers?.fences !== false };
  if (state.layerVersion !== 2) {
    state.layers.fences = true;
    state.layerVersion = 2;
  }
  state.filters = state.filters || {};
  for (const filter of Object.values(state.filters)) {
    if (filter && typeof filter === 'object') { delete filter.area; delete filter.areaId; }
  }
  state.formDrafts = state.formDrafts || {};
  state.selectedMembers = Array.isArray(state.selectedMembers) ? state.selectedMembers : ["P1", "P2", "P3"];
  state.fenceUndo = Array.isArray(state.fenceUndo) ? state.fenceUndo : [];
  // Reload history from the authorized API; never restore an old/demo track on page load.
  state.trackPoints = [];
  state.trackIndex = 0;
  return state;
}

export const session = reactive(load());

watch(
  session,
  (value) => {
    try {
      sessionStorage.setItem("rolling-view", JSON.stringify(value));
    } catch {
      /* 浏览器拒绝写入时保留内存状态。 */
    }
  },
  { deep: true },
);

export function filtersOf(routeName) {
  if (!session.filters[routeName]) session.filters[routeName] = {};
  return session.filters[routeName];
}
