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
import { Circle as CircleStyle, Fill, Stroke, Style } from "ol/style";
import "ol/ol.css";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import { db, tick } from "@/mock/runtime";
import { session } from "@/stores/session";
import { toast } from "@/stores/notify";
import { helmetOf, people } from "@/lib/queries";
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
  personIds: { type: Array, default: null },
  popup: Boolean,
  legend: { type: Boolean, default: true },
  markers: { type: Boolean, default: true },
  mapClass: { type: String, default: "" },
});

const route = useRoute();
const mapEl = ref(null);
const olEl = ref(null);
const scaleText = ref("500 m");
const zones = [
  ["锅炉区", 34, 31],
  ["配电区", 20, 73],
  ["汽机厂房", 52, 73],
  ["循环水区", 81, 35],
];
const areas = [
  [
    [29, 20],
    [43, 20],
    [43, 58],
    [29, 58],
  ],
  [
    [13, 61],
    [29, 61],
    [29, 87],
    [13, 87],
  ],
  [
    [40, 64],
    [65, 64],
    [65, 83],
    [40, 83],
  ],
  [
    [73, 27],
    [90, 27],
    [90, 75],
    [73, 75],
  ],
];

const visiblePeople = computed(() => {
  tick.value;
  const source = props.person ? people().filter((item) => item.id === props.person) : people();
  return source.filter((item) => !props.personIds || props.personIds.includes(item.id));
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
const zoneOverlays = [];
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

function polygonFeature(points, stroke, fill, dash) {
  const feature = new Feature({ geometry: new Polygon([ring(points)]) });
  feature.setStyle(
    new Style({
      stroke: new Stroke({ color: stroke, width: 2.5, lineDash: dash }),
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
  if (session.layers.areas && props.mode !== "fence") {
    areas.forEach((points, index) => {
      shapes.push(polygonFeature(points, index ? "#00e9dd" : "#ffcc42", index ? "#00dac00b" : "#ffcc420a", [6, 4]));
    });
  }
  replaceFeatures(areaSource, shapes);

  const fences = [];
  if (session.layers.fences && props.mode !== "fence") {
    db.state.fences
      .filter((fence) => fence.station === session.station && fence.enabled && !fence.archived)
      .forEach((fence) => fences.push(polygonFeature(fence.points, "#15e1be", "#00bfa021", [7, 3])));
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

function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
}

function ensurePopup() {
  if (popupOverlay || !map) return;
  const element = document.createElement("div");
  element.className = "map-popup";
  popupOverlay = new Overlay({ element, positioning: "bottom-left", offset: [16, -18], stopEvent: true });
  map.addOverlay(popupOverlay);
}

function renderPopup() {
  if (!map) return;
  ensurePopup();
  const person = props.popup ? selected.value : null;
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
  const wanted = showMarkers.value && session.layers.people ? visiblePeople.value : [];
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

function renderZones() {
  if (!map || zoneOverlays.length) return;
  zones.forEach(([label, x, y]) => {
    const element = document.createElement("span");
    element.className = "map-zone";
    element.textContent = label;
    const overlay = new Overlay({
      element,
      position: projected([x, y]),
      positioning: "center-center",
      stopEvent: false,
    });
    map.addOverlay(overlay);
    zoneOverlays.push(overlay);
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
  renderPeople();
  renderPopup();
  renderZones();
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
  if (route.name === "location" || route.name === "overview") return;
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
  const view = map.getView();
  view.setCenter(fromLonLat(PLANT_CENTER));
  view.setZoom(PLANT_ZOOM);
  view.setRotation(0);
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
      new VectorLayer({ source: areaSource, zIndex: 3 }),
      new VectorLayer({ source: fenceSource, zIndex: 4 }),
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
  observer = new ResizeObserver(() => map.updateSize());
  observer.observe(mapEl.value);
  render();
  updateScale();
});

onUnmounted(() => {
  observer?.disconnect();
  personOverlays.clear();
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
    props.popup,
    props.markers,
  ],
  () => render(),
  { deep: true },
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
      <AppIcon name="user-fill" color="blue" /> 人员位置<br />
      <AppIcon name="checkbox-blank-line" color="cyan" /> 作业区域<br />
      <AppIcon name="error-warning-line" color="yellow" /> 待核验位置
    </div>
    <div class="map-scale">{{ scaleText }}<hr /></div>
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
