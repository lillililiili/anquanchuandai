import { reactive, watch } from "vue";

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
    layers: { people: true, areas: true, fences: false },
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
    captcha: "K7M2",
    broadcastDraft: "",
    showPassword: false,
  };
}

function load() {
  const state = defaults();
  try {
    const saved = JSON.parse(sessionStorage.getItem("rolling-view") || "null");
    if (saved && typeof saved === "object") Object.assign(state, saved);
  } catch {
    /* 损坏的会话不阻止进入演示。 */
  }
  state.station = localStorage.getItem("rolling-station") || state.station || "S1";
  state.recording = null;
  state.trackPlaying = false;
  state.layers = { people: true, areas: true, fences: false, ...state.layers };
  state.filters = state.filters || {};
  state.formDrafts = state.formDrafts || {};
  state.selectedMembers = Array.isArray(state.selectedMembers) ? state.selectedMembers : ["P1", "P2", "P3"];
  state.fenceUndo = Array.isArray(state.fenceUndo) ? state.fenceUndo : [];
  state.trackPoints = Array.isArray(state.trackPoints) ? state.trackPoints : [];
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
