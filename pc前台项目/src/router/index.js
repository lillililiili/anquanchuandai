import { createRouter, createWebHashHistory } from "vue-router";
import { closeModal } from "@/stores/modal";

const auth = { auth: true };

export const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: "/", redirect: () => (sessionStorage.getItem("rolling-session") ? "/overview" : "/login") },
    { path: "/login", name: "login", component: () => import("@/views/login/LoginView.vue") },
    { path: "/overview", name: "overview", meta: auth, component: () => import("@/views/overview/OverviewView.vue") },
    { path: "/personnel", name: "personnel", meta: auth, component: () => import("@/views/personnel/PersonnelView.vue") },
    { path: "/person/:id", name: "person", meta: auth, component: () => import("@/views/person/PersonView.vue") },
    { path: "/works", name: "works", meta: auth, component: () => import("@/views/works/WorksView.vue") },
    { path: "/work/:id", name: "work", meta: auth, component: () => import("@/views/work/WorkView.vue") },
    { path: "/video", name: "video", meta: auth, component: () => import("@/views/video/VideoView.vue") },
    { path: "/single/:id", name: "single", meta: auth, component: () => import("@/views/single/SingleView.vue") },
    { path: "/materials", name: "materials", meta: auth, component: () => import("@/views/materials/MaterialsView.vue") },
    { path: "/location", name: "location", meta: auth, component: () => import("@/views/location/LocationView.vue") },
    { path: "/tracks/:id?", name: "tracks", meta: auth, component: () => import("@/views/tracks/TracksView.vue") },
    { path: "/fences", name: "fences", meta: auth, component: () => import("@/views/fences/FencesView.vue") },
    { path: "/alarms", name: "alarms", meta: auth, component: () => import("@/views/alarms/AlarmsView.vue") },
    { path: "/event/:id", name: "event", meta: auth, component: () => import("@/views/event/EventView.vue") },
    { path: "/dispatch", name: "dispatch", meta: auth, component: () => import("@/views/dispatch/DispatchView.vue") },
    { path: "/sos", name: "sos", meta: auth, component: () => import("@/views/sos/SosView.vue") },
    { path: "/statistics", name: "statistics", meta: auth, component: () => import("@/views/statistics/StatisticsView.vue") },
  ],
});

router.beforeEach((to) => {
  if (to.meta.auth && !sessionStorage.getItem("rolling-session")) return { name: "login" };
});

router.afterEach(() => closeModal());
