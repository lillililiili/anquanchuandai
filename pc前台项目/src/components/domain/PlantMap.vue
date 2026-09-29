<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import { useRoute } from "vue-router";
import OlMap from "ol/Map";
import View from "ol/View";
import TileLayer from "ol/layer/Tile";
import XYZ from "ol/source/XYZ";
import VectorLayer from "ol/layer/Vector";
import VectorSource from "ol/source/Vector";
import Feature from "ol/Feature";
import Point from "ol/geom/Point";
import LineString from "ol/geom/LineString";
import Polygon from "ol/geom/Polygon";
import Overlay from "ol/Overlay";
import DragPan from "ol/interaction/DragPan";
import { defaults as defaultInteractions } from "ol/interaction/defaults";
import { fromLonLat, toLonLat } from "ol/proj";
import { boundingExtent } from "ol/extent";
import { Circle as CircleStyle, Fill, Stroke, Style } from "ol/style";
import "ol/ol.css";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import { db, tick } from "@/mock/runtime";
import { session } from "@/stores/session";
import { toast } from "@/stores/notify";
import { helmetOf, people } from "@/lib/queries";
import { areaOccupancy, displayedAreas, validPosition } from "./map-areas.js";
import {
  LABEL_TILES,
  MAX_ZOOM,
  MIN_ZOOM,
  PLANT_CENTER,
  PLANT_ZOOM,
  SATELLITE_TILES,
  clampPercent,
  lonLatToPercent,
  percentToLonLat,
} from "./map-geo.js";

const props = defineProps({
  mode: { type: String, default: "live" },
  person: { type: String, default: "" },
  focusPerson: Boolean,
  focusKey: { type: String, default: "" },
  personIds: { type: Array, default: null },
  work: { type: Object, default: null },
  popup: Boolean,
  legend: { type: Boolean, default: true },
  markers: { type: Boolean, default: true },
  fences: { type: Boolean, default: true },
  areaCounts: Boolean,
  mapClass: { type: String, default: "" },
});

const route = useRoute();
const mapEl = ref(null);
const olEl = ref(null);
const scaleText = ref("500 m");
const occupancy = computed(() => {
  tick.value;
  return areaOccupancy(db.state, session.station, (id) => db.locationValid(id));
});
const visiblePeople = computed(() => {
  tick.value;
  if (props.focusPerson && !props.person) return [];
  const source = props.person ? people().filter((item) => item.id === props.person) : people();
  return source.filter((item) =>
    (!props.personIds || props.personIds.includes(item.id)) &&
    (!props.work || props.work.members?.includes(item.id)),
  );
});
const visibleAreas = computed(() => {
  tick.value;
  const areas = displayedAreas(db.state, session.station);
  if (!props.work) return areas;
  const area = areas.find((item) => props.work.areaId ? item.id === props.work.areaId : item.name === props.work.area);
  return area ? [area] : [];
});
const workFocusPoints = computed(() => {
  if (!props.work) return [];
  return [
    ...visibleAreas.value.flatMap((area) => area.points),
    ...visiblePeople.value.map((person) => person.position).filter(validPosition),
  ];
});
const showMarkers = computed(() => props.markers !== false && props.mode !== "fence");
const selected = computed(() => {
  tick.value;
  return db.person(props.person || session.person);
});

let map;
let dragPan;
let observer;
let dragging = null;
const personOverlays = new Map();
const areaOverlays = new Map();
const hoveredId = ref("");
let hideTimer = 0;
let popupOverlay;

const areaSource = new VectorSource();
const fenceSource = new VectorSource();
const trackSource = new VectorSource();
const draftSource = new VectorSource();

function workName(personId) {
  return db.currentWork(personId)?.name || "待分配";
}

function projected(point) {
  return fromLonLat(percentToLonLat(point));
}

function percentFromCoordinate(coordinate) {
  return clampPercent(lonLatToPercent(toLonLat(coordinate)));
}

function ring(points) {
  const line = points.map((point) => projected(point));
  if (line.length && (line[0][0] !== line[line.length - 1][0] || line[0][1] !== line[line.length - 1][1])) {
    line.push(line[0]);
  }
  return line;
}

function polygonFeature(points, stroke, fill, dash, width = 2.5) {
  const feature = new Feature({ geometry: new Polygon([ring(points)]) });
  feature.setStyle(
    new Style({
      stroke: new Stroke({ color: stroke, width, lineDash: dash }),
      fill: new Fill({ color: fill }),
    }),
  );
  return feature;
}

function circleFeature(point, radius, fill, stroke) {
  const feature = new Feature({ geometry: new Point(projected(point)) });
  feature.setStyle(
    new Style({
      image: new CircleStyle({
        radius,
        fill: new Fill({ color: fill }),
        stroke: new Stroke({ color: stroke, width: 2 }),
      }),
    }),
  );
  return feature;
}

function lineFeature(points, color) {
  const feature = new Feature({ geometry: new LineString(points.map((point) => projected([point.x, point.y]))) });
  feature.setStyle(
    new Style({
      stroke: new Stroke({ color, width: 4 }),
    }),
  );
  return feature;
}

function trackGroups(points) {
  const groups = [];
  points.forEach((point) => {
    if (!groups.length || point.gap) groups.push([point]);
    else groups[groups.length - 1].push(point);
  });
  return groups.filter((group) => group.length > 1);
}

function replaceFeatures(source, features) {
  source.clear();
  source.addFeatures(features);
}

function renderShapes() {
  const shapes = [];
  if ((props.work || props.areaCounts || session.layers.areas) && props.mode !== "fence") {
    visibleAreas.value.forEach((area) => {
      shapes.push(polygonFeature(area.points, "#09dce3", "rgba(9, 220, 227, 0.04)", [8, 6], 2));
    });
  }
  replaceFeatures(areaSource, shapes);

  const fences = [];
  if (props.fences && (props.areaCounts || session.layers.fences) && props.mode !== "fence") {
    db.state.fences
      .filter((fence) => fence.station === session.station && fence.enabled && !fence.archived)
      .forEach((fence) => fences.push(polygonFeature(fence.points, "#1ce3b1", "rgba(28, 227, 177, 0.22)")));
  }
  replaceFeatures(fenceSource, fences);

  const draft = [];
  if (props.mode === "fence" && session.fenceDraft) {
    if (session.fenceDraft.points.length) {
      draft.push(polygonFeature(session.fenceDraft.points, "#20b9ff", "#1294fa44", [5, 4]));
    }
    session.fenceDraft.points.forEach((point) => draft.push(circleFeature(point, 7, "#168bff", "#e7faff")));
  }
  replaceFeatures(draftSource, draft);

  const tracks = [];
  if (props.mode === "tracks") {
    const points = session.trackPoints;
    trackGroups(points).forEach((group) => tracks.push(lineFeature(group, "#09d9ff")));
    points.forEach((point, index) => {
      const active = index === session.trackIndex;
      tracks.push(circleFeature([point.x, point.y], active ? 8 : 5, active ? "#008fff" : "#def9ff", active ? "#ffffff" : "#00bfff"));
    });
  }
  replaceFeatures(trackSource, tracks);
}

function renderAreaLabels() {
  const areas = props.areaCounts && props.mode !== "fence" ? occupancy.value.areas : [];
  const ids = new Set(areas.map((area) => area.id));
  for (const [id, overlay] of areaOverlays) {
    if (ids.has(id)) continue;
    map.removeOverlay(overlay);
    areaOverlays.delete(id);
  }
  areas.forEach((area) => {
    let overlay = areaOverlays.get(area.id);
    if (!overlay) {
      const element = document.createElement("div");
      overlay = new Overlay({ element, positioning: "center-center", stopEvent: false });
      map.addOverlay(overlay);
      areaOverlays.set(area.id, overlay);
    }
    const element = overlay.getElement();
    element.className = "map-zone map-zone-count";
    element.dataset.areaId = area.id;
    element.setAttribute("aria-label", `有效定位 ${area.personIds.length} 人`);
    element.innerHTML = `<strong>${area.personIds.length}<small> 人</small></strong>`;
    overlay.setPosition(new Polygon([ring(area.points)]).getInteriorPoint().getCoordinates());
  });
}

function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
}

function showPersonCard(id) {
  window.clearTimeout(hideTimer);
  if (hoveredId.value !== id) hoveredId.value = id;
}

function hidePersonCard() {
  window.clearTimeout(hideTimer);
  hideTimer = window.setTimeout(() => {
    hoveredId.value = "";
  }, 160);
}

function ensurePopup() {
  if (popupOverlay || !map) return;
  const element = document.createElement("div");
  element.className = "map-popup";
  element.addEventListener("pointerenter", () => window.clearTimeout(hideTimer));
  element.addEventListener("pointerleave", hidePersonCard);
  popupOverlay = new Overlay({ element, positioning: "bottom-left", offset: [26, -26], stopEvent: true });
  map.addOverlay(popupOverlay);
}

function renderPopup() {
  if (!map) return;
  ensurePopup();
  const person = props.popup ? visiblePeople.value.find((item) => item.id === hoveredId.value && validPosition(item.position)) : null;
  if (!person) {
    popupOverlay.setPosition(undefined);
    return;
  }
  const valid = db.locationValid(person.id);
  popupOverlay.getElement().innerHTML =
    `<b>${esc(person.name)}</b>　${esc(helmetOf(person.id)?.id || "未绑定")}` +
    `<p>作业：${esc(workName(person.id))}</p>` +
    `<p>位置：${esc(person.area)}　<span class="status ${valid ? "green" : "yellow"}"><b></b>${valid ? "位置有效" : "待核验"}</span></p>` +
    `<div class="row"><a class="text-link" href="#/tracks/${esc(person.id)}">历史轨迹 →</a><a class="text-link" href="#/person/${esc(person.id)}">查看人员</a></div>`;
  popupOverlay.setPosition(projected(person.position));
}

function renderPeople() {
  if (!map) return;
  const wanted = showMarkers.value && (props.focusPerson || props.work || props.areaCounts || session.layers.people) ? visiblePeople.value.filter((person) => validPosition(person.position)) : [];
  const ids = new Set(wanted.map((person) => person.id));
  for (const [id, overlay] of personOverlays) {
    if (ids.has(id)) continue;
    map.removeOverlay(overlay);
    personOverlays.delete(id);
  }
  wanted.forEach((person) => {
    let overlay = personOverlays.get(person.id);
    if (!overlay) {
      const button = document.createElement("button");
      button.type = "button";
      button.innerHTML = '<i class="ri-user-fill" aria-hidden="true"></i>';
      button.addEventListener("click", (event) => {
        event.stopPropagation();
        choose(button.dataset.id);
      });
      button.addEventListener("pointerenter", () => showPersonCard(button.dataset.id));
      button.addEventListener("pointerleave", hidePersonCard);
      overlay = new Overlay({ element: button, positioning: "center-center", stopEvent: true });
      map.addOverlay(overlay);
      personOverlays.set(person.id, overlay);
    }
    const button = overlay.getElement();
    button.dataset.id = person.id;
    button.className = [
      "map-person",
      db.locationValid(person.id) ? "" : "warning",
      selected.value?.id === person.id ? "selected" : "",
    ]
      .filter(Boolean)
      .join(" ");
    button.setAttribute("aria-label", "定位 " + person.name);
    overlay.setPosition(projected(person.position));
  });
}

function syncPan() {
  if (!dragPan) return;
  const drawing = props.mode === "fence" && (session.fenceMode === "draw" || session.fenceMode === "edit");
  dragPan.setActive(!drawing);
}

function render() {
  if (!map) return;
  renderShapes();
  renderAreaLabels();
  renderPeople();
  renderPopup();
  syncPan();
}

function updateScale() {
  if (!map) return;
  const view = map.getView();
  const resolution = view.getResolution() || 1;
  const ground = resolution * Math.cos((PLANT_CENTER[1] * Math.PI) / 180);
  const meters = ground * 96;
  const steps = [50, 100, 200, 500, 1000, 2000, 5000, 10000];
  const nice = steps.find((step) => step >= meters) || steps[steps.length - 1];
  scaleText.value = nice >= 1000 ? `0　　${nice / 1000} km` : `0　　${nice} m`;
}

function choose(id) {
  session.person = id;
  if (route.name === "location" || route.name === "overview" || route.name === "screen") {
    showPersonCard(id);
    return;
  }
  location.hash = "#/person/" + id;
}

function zoomBy(delta) {
  if (!map) return;
  const view = map.getView();
  const next = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, (view.getZoom() || PLANT_ZOOM) + delta));
  view.setZoom(next);
}

function resetView() {
  if (!map) return;
  if (props.work || props.focusPerson) {
    focusSelection();
    return;
  }
  const view = map.getView();
  view.setCenter(fromLonLat(PLANT_CENTER));
  view.setZoom(PLANT_ZOOM);
  view.setRotation(0);
}

function focusWork() {
  if (!map || !props.work) return;
  map.updateSize();
  const size = map.getSize();
  if (!size || size.some((value) => value <= 0)) return;
  const view = map.getView();
  view.cancelAnimations();
  view.setRotation(0);
  if (workFocusPoints.value.length) {
    // Leave room for the caption, controls and marker radius in the compact map.
    view.fit(boundingExtent(workFocusPoints.value.map(projected)), {
      size,
      padding: [48, 64, 36, 32],
      maxZoom: MAX_ZOOM,
    });
  } else {
    view.setCenter(fromLonLat(PLANT_CENTER));
    view.setZoom(PLANT_ZOOM);
  }
}

function focusSelection() {
  if (props.work) {
    focusWork();
    return;
  }
  if (!map || !props.focusPerson) return;
  map.updateSize();
  const size = map.getSize();
  if (!size || size.some((value) => value <= 0)) return;
  const view = map.getView();
  const person = visiblePeople.value.find((item) => item.id === props.person && validPosition(item.position));
  view.cancelAnimations();
  view.setRotation(0);
  if (person) {
    view.fit(new Point(projected(person.position)), {
      size,
      padding: [48, 64, 32, 32],
      maxZoom: PLANT_ZOOM,
    });
  } else {
    view.setCenter(fromLonLat(PLANT_CENTER));
    view.setZoom(PLANT_ZOOM);
  }
}

function setMode(mode) {
  if (!session.fenceDraft) {
    toast("请先新建或选择围栏", true);
    return;
  }
  session.fenceMode = mode;
}

function undo() {
  if (!session.fenceUndo.length) {
    toast("没有可撤销的编辑", true);
    return;
  }
  session.fenceDraft.points = session.fenceUndo.pop();
}

function rememberPoints() {
  session.fenceUndo.push(session.fenceDraft.points.map((point) => [Number(point[0]), Number(point[1])]));
}

function onSingleClick(event) {
  if (props.mode !== "fence" || !session.fenceDraft || session.fenceMode !== "draw") return;
  rememberPoints();
  session.fenceDraft.points.push(percentFromCoordinate(event.coordinate));
}

function onDoubleClick(event) {
  if (props.mode === "fence" && session.fenceMode === "draw") {
    event.preventDefault();
    session.fenceMode = "edit";
    toast("绘制完成，可拖动节点调整");
  }
}

function onPointerDown(event) {
  if (props.mode !== "fence" || session.fenceMode !== "edit" || !session.fenceDraft) return;
  const point = percentFromCoordinate(event.coordinate);
  const index = session.fenceDraft.points.findIndex((item) => Math.hypot(item[0] - point[0], item[1] - point[1]) < 3);
  if (index < 0) return;
  rememberPoints();
  dragging = index;
  event.preventDefault();
}

function onPointerMove(event) {
  if (dragging == null || !session.fenceDraft) return;
  session.fenceDraft.points[dragging] = percentFromCoordinate(event.coordinate);
}

function onPointerUp() {
  dragging = null;
}

onMounted(() => {
  map = new OlMap({
    target: olEl.value,
    layers: [
      new TileLayer({ source: new XYZ({ url: SATELLITE_TILES }) }),
      new TileLayer({ source: new XYZ({ url: LABEL_TILES }) }),
      new VectorLayer({ source: fenceSource, zIndex: 3 }),
      new VectorLayer({ source: areaSource, zIndex: 4 }),
      new VectorLayer({ source: trackSource, zIndex: 5 }),
      new VectorLayer({ source: draftSource, zIndex: 6 }),
    ],
    view: new View({
      center: fromLonLat(PLANT_CENTER),
      zoom: PLANT_ZOOM,
      minZoom: MIN_ZOOM,
      maxZoom: MAX_ZOOM,
    }),
    controls: [],
    interactions: defaultInteractions({ doubleClickZoom: false, altShiftDragRotate: false, pinchRotate: false }),
  });
  dragPan = map
    .getInteractions()
    .getArray()
    .find((item) => item instanceof DragPan);
  map.on("singleclick", onSingleClick);
  map.on("dblclick", onDoubleClick);
  map.on("pointerdown", onPointerDown);
  map.on("pointermove", onPointerMove);
  map.on("pointerup", onPointerUp);
  map.on("moveend", updateScale);
  observer = new ResizeObserver(() => {
    map.updateSize();
    focusSelection();
  });
  observer.observe(mapEl.value);
  render();
  focusSelection();
  updateScale();
});

onUnmounted(() => {
  window.clearTimeout(hideTimer);
  observer?.disconnect();
  personOverlays.clear();
  areaOverlays.clear();
  map?.setTarget(null);
  map?.dispose();
  map = null;
});

watch(
  () => [
    tick.value,
    session.person,
    session.layers.people,
    session.layers.areas,
    session.layers.fences,
    session.station,
    session.trackIndex,
    session.trackPoints,
    session.fenceDraft,
    session.fenceMode,
    props.mode,
    props.person,
    props.focusPerson,
    props.popup,
    props.markers,
    props.fences,
    props.areaCounts,
    props.personIds,
    props.work,
    hoveredId.value,
  ],
  () => render(),
  { deep: true },
);

watch(
  () => [props.work?.id, session.station, JSON.stringify(workFocusPoints.value)],
  () => focusWork(),
  { flush: "post" },
);

watch(
  () => [props.focusPerson, props.focusKey, props.person, session.station,
    props.focusPerson ? JSON.stringify(visiblePeople.value.map((person) => person.position)) : ""],
  () => { if (props.focusPerson) focusSelection(); },
  { flush: "post" },
);
</script>

<template>
  <div ref="mapEl" :class="['map', mapClass]" :data-map="mode" :data-person="person">
    <div ref="olEl" class="map-ol"></div>
    <div class="map-caption">阳城电厂卫星图 · 示意位置</div>
    <div class="map-compass">N<br /><AppIcon name="navigation-fill" /></div>
    <div class="map-tools">
      <AppButton tone="icon-only" icon="crosshair-2-line" aria-label="重置地图" @click="resetView" />
      <AppButton tone="icon-only" icon="add-line" aria-label="放大地图" @click="zoomBy(1)" />
      <AppButton tone="icon-only" icon="subtract-line" aria-label="缩小地图" @click="zoomBy(-1)" />
    </div>
    <div v-if="legend" class="map-legend">
      图例<br />
      <template v-if="showMarkers"><AppIcon name="user-fill" color="blue" /> 人员位置<br /></template>
      <AppIcon name="checkbox-blank-line" color="cyan" /> 作业区域<br />
      <template v-if="fences"><AppIcon name="shape-line" color="green" /> 电子围栏<br /></template>
      <template v-if="showMarkers"><AppIcon name="error-warning-line" color="yellow" /> 待核验位置</template>
    </div>
    <div class="map-scale">{{ scaleText }}<hr /></div>
    <div v-if="areaCounts" class="map-area-summary" aria-label="作业区域人数统计">
      <span>有效定位人数</span>
      <span>区域内 <b>{{ occupancy.inside }}</b></span>
      <span>{{ occupancy.areas.length ? "区域外" : "未配置区域" }} <b>{{ occupancy.outside }}</b></span>
      <span class="map-count-unverified">待核验 <b>{{ occupancy.unverified }}</b></span>
      <small v-if="occupancy.overlapping">重叠区域分别计数，区域内总人数已去重</small>
    </div>
    <template v-if="mode === 'fence'">
      <div class="map-editbar">
        <AppButton :tone="session.fenceMode === 'select' ? 'primary' : ''" icon="cursor-line" @click="setMode('select')">选择</AppButton>
        <AppButton :tone="session.fenceMode === 'draw' ? 'primary' : ''" icon="shape-line" @click="setMode('draw')">绘制区域</AppButton>
        <AppButton :tone="session.fenceMode === 'edit' ? 'primary' : ''" icon="node-tree" @click="setMode('edit')">编辑节点</AppButton>
        <AppButton icon="arrow-go-back-line" @click="undo">撤销</AppButton>
      </div>
      <div class="map-instruction">
        {{ session.fenceMode === "draw" ? "单击添加节点，双击完成绘制" : session.fenceMode === "edit" ? "拖动节点调整区域，保存后生效" : "拖动地图平移，使用右侧按钮缩放" }}
      </div>
    </template>
  </div>
</template>
