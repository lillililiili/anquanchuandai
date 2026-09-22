<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import { useRoute } from "vue-router";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import { db, tick } from "@/mock/runtime";
import { session } from "@/stores/session";
import { toast } from "@/stores/notify";
import { helmetOf, people } from "@/lib/queries";

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
const worldEl = ref(null);
const canvasEl = ref(null);
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

let zoom = 1;
let pan = [0, 0];
let drag = null;
let observer;
let context;

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

function workName(personId) {
  return db.currentWork(personId)?.name || "待分配";
}

function applyTransform() {
  if (!worldEl.value) return;
  worldEl.value.style.transform = `translate(${pan[0]}px,${pan[1]}px) scale(${zoom})`;
}

function paint() {
  const element = mapEl.value;
  const canvas = canvasEl.value;
  if (!element || !canvas) return;
  context ||= canvas.getContext("2d");
  const ctx = context;
  const width = element.clientWidth;
  const height = element.clientHeight;
  if (!width || !height) return;
  canvas.width = width * devicePixelRatio;
  canvas.height = height * devicePixelRatio;
  ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
  ctx.clearRect(0, 0, width, height);
  const poly = (points, color, fill, dash = []) => {
    if (!points?.length) return;
    ctx.beginPath();
    points.forEach((point, index) => {
      const x = (point[0] * width) / 100;
      const y = (point[1] * height) / 100;
      if (index) ctx.lineTo(x, y);
      else ctx.moveTo(x, y);
    });
    ctx.closePath();
    ctx.strokeStyle = color;
    ctx.fillStyle = fill;
    ctx.lineWidth = 2.5;
    ctx.setLineDash(dash);
    ctx.fill();
    ctx.stroke();
    ctx.setLineDash([]);
  };
  if (session.layers.areas && props.mode !== "fence") {
    areas.forEach((points, index) => poly(points, index ? "#00e9dd" : "#ffcc42", index ? "#00dac00b" : "#ffcc420a", [6, 4]));
  }
  if (session.layers.fences && props.mode !== "fence") {
    db.state.fences
      .filter((fence) => fence.station === session.station && fence.enabled && !fence.archived)
      .forEach((fence) => poly(fence.points, "#15e1be", "#00bfa021", [7, 3]));
  }
  if (props.mode === "fence" && session.fenceDraft) {
    poly(session.fenceDraft.points, "#20b9ff", "#1294fa44", [5, 4]);
    session.fenceDraft.points.forEach((point) => {
      ctx.beginPath();
      ctx.arc((point[0] * width) / 100, (point[1] * height) / 100, 7, 0, Math.PI * 2);
      ctx.fillStyle = "#168bff";
      ctx.fill();
      ctx.strokeStyle = "#e7faff";
      ctx.lineWidth = 3;
      ctx.stroke();
    });
  }
  if (props.mode === "tracks") {
    const points = session.trackPoints;
    ctx.lineWidth = 4;
    ctx.strokeStyle = "#09d9ff";
    ctx.shadowColor = "#00aaff";
    ctx.shadowBlur = 7;
    ctx.beginPath();
    points.forEach((point, index) => {
      const x = (point.x * width) / 100;
      const y = (point.y * height) / 100;
      if (!index || point.gap) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();
    ctx.shadowBlur = 0;
    points.forEach((point) => {
      ctx.beginPath();
      ctx.arc((point.x * width) / 100, (point.y * height) / 100, 5, 0, Math.PI * 2);
      ctx.fillStyle = "#def9ff";
      ctx.fill();
      ctx.strokeStyle = "#00bfff";
      ctx.lineWidth = 2;
      ctx.stroke();
    });
    const current = points[session.trackIndex];
    if (current) {
      ctx.beginPath();
      ctx.arc((current.x * width) / 100, (current.y * height) / 100, 13, 0, Math.PI * 2);
      ctx.fillStyle = "#008fff";
      ctx.fill();
      ctx.strokeStyle = "white";
      ctx.stroke();
    }
  }
}

function pointOf(event) {
  const bounds = worldEl.value.getBoundingClientRect();
  return [
    Math.max(0, Math.min(100, ((event.clientX - bounds.left) / bounds.width) * 100)),
    Math.max(0, Math.min(100, ((event.clientY - bounds.top) / bounds.height) * 100)),
  ];
}

function onPointerDown(event) {
  if (event.target.closest("button,.map-popup,.map-editbar")) return;
  if (props.mode === "fence" && session.fenceDraft && session.fenceMode === "draw") {
    if (event.detail > 1) return;
    session.fenceUndo.push(structuredClone(session.fenceDraft.points));
    session.fenceDraft.points.push(pointOf(event));
    paint();
    return;
  }
  if (props.mode === "fence" && session.fenceDraft && session.fenceMode === "edit") {
    const point = pointOf(event);
    const index = session.fenceDraft.points.findIndex((item) => Math.hypot(item[0] - point[0], item[1] - point[1]) < 3);
    if (index >= 0) {
      session.fenceUndo.push(structuredClone(session.fenceDraft.points));
      drag = { node: index };
    }
  } else drag = { start: [event.clientX, event.clientY], pan: [...pan] };
  if (drag) mapEl.value.setPointerCapture(event.pointerId);
}

function onPointerMove(event) {
  if (!drag) return;
  if (drag.node !== undefined) {
    session.fenceDraft.points[drag.node] = pointOf(event);
    paint();
    return;
  }
  pan = [drag.pan[0] + event.clientX - drag.start[0], drag.pan[1] + event.clientY - drag.start[1]];
  applyTransform();
}

function onPointerUp() {
  drag = null;
}

function onDoubleClick() {
  if (props.mode === "fence" && session.fenceMode === "draw") {
    session.fenceMode = "edit";
    toast("绘制完成，可拖动节点调整");
  }
}

function choose(id) {
  session.person = id;
  if (route.name === "location" || route.name === "overview") return;
  location.hash = "#/person/" + id;
}

function setZoom(next) {
  zoom = next;
  applyTransform();
}

function resetView() {
  zoom = 1;
  pan = [0, 0];
  applyTransform();
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
  paint();
}

function popupStyle(person) {
  return {
    left: Math.min(60, person.position[0] + 3) + "%",
    top: Math.max(3, person.position[1] - 31) + "%",
  };
}

onMounted(() => {
  observer = new ResizeObserver(() => paint());
  observer.observe(mapEl.value);
  paint();
});

onUnmounted(() => observer?.disconnect());

watch(
  () => [
    tick.value,
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
  ],
  () => paint(),
  { deep: true },
);
</script>

<template>
  <div
    ref="mapEl"
    :class="['map', mapClass]"
    :data-map="mode"
    :data-person="person"
    @pointerdown="onPointerDown"
    @pointermove="onPointerMove"
    @pointerup="onPointerUp"
    @dblclick="onDoubleClick"
  >
    <div ref="worldEl" class="map-world">
      <img src="/assets/plant-map.png" alt="厂区示意底图" />
      <canvas ref="canvasEl" aria-label="作业区域与轨迹图层"></canvas>
      <div class="map-labels">
        <span v-for="[label, x, y] in zones" :key="label" class="map-zone" :style="{ left: x + '%', top: y + '%' }">{{ label }}</span>
      </div>
      <button
        v-for="person in showMarkers && session.layers.people ? visiblePeople : []"
        :key="person.id"
        type="button"
        :class="['map-person', db.locationValid(person.id) ? '' : 'warning', selected?.id === person.id ? 'selected' : '']"
        :style="{ left: person.position[0] + '%', top: person.position[1] + '%' }"
        :aria-label="'定位 ' + person.name"
        @click="choose(person.id)"
      >
        <AppIcon name="user-fill" />
      </button>
      <div v-if="popup && selected" class="map-popup" :style="popupStyle(selected)">
        <b>{{ selected.name }}</b>　{{ helmetOf(selected.id)?.id || "未绑定" }}
        <p>作业：{{ workName(selected.id) }}</p>
        <p>
          位置：{{ selected.area }}　<AppStatus :color="db.locationValid(selected.id) ? 'green' : 'yellow'">{{ db.locationValid(selected.id) ? "位置有效" : "待核验" }}</AppStatus>
        </p>
        <div class="row">
          <a class="text-link" :href="'#/tracks/' + selected.id">历史轨迹 →</a>
          <a class="text-link" :href="'#/person/' + selected.id">查看人员</a>
        </div>
      </div>
    </div>
    <div class="map-caption">厂区示意 · 非实测</div>
    <div class="map-compass">N<br /><AppIcon name="navigation-fill" /></div>
    <div class="map-tools">
      <AppButton tone="icon-only" icon="crosshair-2-line" aria-label="重置地图" @click="resetView" />
      <AppButton tone="icon-only" icon="add-line" aria-label="放大地图" @click="setZoom(Math.min(3, zoom + 0.2))" />
      <AppButton tone="icon-only" icon="subtract-line" aria-label="缩小地图" @click="setZoom(Math.max(1, zoom - 0.2))" />
    </div>
    <div v-if="legend" class="map-legend">
      图例<br />
      <AppIcon name="user-fill" color="blue" /> 人员位置<br />
      <AppIcon name="checkbox-blank-line" color="cyan" /> 作业区域<br />
      <AppIcon name="error-warning-line" color="yellow" /> 待核验位置
    </div>
    <div class="map-scale">0　　　　 250　　　500 m<hr /></div>
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
