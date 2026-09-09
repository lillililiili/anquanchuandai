<template>
  <div class="app-container">
    <ModuleHeader
      module="system"
      title="人员位置"
      description="主位置只来自当前领用安全帽的 GNSS。安全带不打点。楼层未知不编造。陈旧/未知不是违章。"
    />
    <div v-if="plotted.length" class="plot" aria-label="人员位置示意">
      <button
        v-for="p in plotted"
        :key="p.personId"
        type="button"
        class="plot-dot"
        :class="p.locationQuality"
        :style="{ left: p.x + '%', top: p.y + '%' }"
        @click="openDetail(p)"
      >{{ p.personName }}</button>
    </div>
    <p v-else class="hint">无人有坐标，无法绘制平面示意。楼层未知，不编造分层。</p>
    <el-table v-loading="loading" class="custom-table" :data="list" @row-click="openDetail">
      <template #empty><BrandedEmpty compact description="暂无人员位置" /></template>
      <el-table-column label="人员" min-width="140">
        <template #default="scope">{{ scope.row.personName }} {{ scope.row.personCode }}</template>
      </el-table-column>
      <el-table-column label="帽 SN" prop="sn" width="140" />
      <el-table-column label="坐标" min-width="180">
        <template #default="scope">{{ coordText(scope.row) }}</template>
      </el-table-column>
      <el-table-column label="位置质量" width="110">
        <template #default="scope">
          <el-tag :type="qualityType(scope.row.locationQuality)" size="small">{{ locationQualityLabel(scope.row.locationQuality) }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="连接" width="100">
        <template #default="scope">
          <el-tag :type="qualityType(scope.row.connectionQuality)" size="small">{{ locationQualityLabel(scope.row.connectionQuality) }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column label="楼层" width="90">
        <template #default="scope">未知</template>
      </el-table-column>
    </el-table>
    <pagination v-show="total > 0" v-model:page="queryParams.current" v-model:limit="queryParams.size" :total="total" @pagination="getList" />

    <el-dialog v-model="detailOpen" title="位置与轨迹" width="640px">
      <p>人员：{{ detail.personName }} {{ detail.personCode }}</p>
      <p>来源：{{ detail.source === 'helmet' ? '安全帽' : '无' }}　SN：{{ detail.sn || '-' }}</p>
      <p>坐标：{{ coordText(detail) }}　质量：{{ locationQualityLabel(detail.locationQuality) }}</p>
      <p>楼层：未知（{{ detail.floorSource || 'unknown' }}）　发生：{{ detail.occurredAt || '-' }}</p>
      <p>轨迹（最近 24 小时，含陈旧点但不作违章）：</p>
      <p v-for="(p, i) in tracks" :key="i">{{ p.occurredAt }} {{ p.lat }}, {{ p.lng }} {{ locationQualityLabel(p.locationQuality) }} {{ p.sn }}</p>
      <p v-if="!tracks.length">无轨迹点。</p>
    </el-dialog>
  </div>
</template>

<script setup>
import { listPersonLocations, getPersonLocation, listPersonTracks, locationQualityLabel } from '@/api/wear/locations'
import useUserStore from '@/store/modules/user'

const userStore = useUserStore()

const loading = ref(false)
const list = ref([])
const total = ref(0)
const queryParams = reactive({ current: 1, size: 10 })
const detailOpen = ref(false)
const detail = ref({})
const tracks = ref([])

function unwrap(res) {
  return res && res.data !== undefined ? res.data : res
}

function coordText(row) {
  if (row == null || row.lat == null || row.lng == null) return '无坐标'
  return row.lat + ', ' + row.lng
}

function qualityType(q) {
  if (q === 'ok') return 'success'
  if (q === 'stale') return 'warning'
  return 'info'
}

const plotted = computed(() => {
  const pts = (list.value || []).filter(p => p.lat != null && p.lng != null)
  if (!pts.length) return []
  let minLat = pts[0].lat
  let maxLat = pts[0].lat
  let minLng = pts[0].lng
  let maxLng = pts[0].lng
  pts.forEach(p => {
    minLat = Math.min(minLat, p.lat)
    maxLat = Math.max(maxLat, p.lat)
    minLng = Math.min(minLng, p.lng)
    maxLng = Math.max(maxLng, p.lng)
  })
  const dLat = maxLat - minLat || 0.01
  const dLng = maxLng - minLng || 0.01
  return pts.map(p => ({
    ...p,
    x: ((p.lng - minLng) / dLng) * 80 + 10,
    y: (1 - (p.lat - minLat) / dLat) * 70 + 10
  }))
})

function getList() {
  if (!userStore.currentSiteId) {
    list.value = []
    total.value = 0
    return
  }
  loading.value = true
  listPersonLocations(queryParams).then(res => {
    const page = unwrap(res) || {}
    list.value = page.records || []
    total.value = page.total || 0
  }).finally(() => { loading.value = false })
}

function openDetail(row) {
  getPersonLocation(row.personId).then(res => {
    detail.value = unwrap(res) || row
    detailOpen.value = true
  })
  const to = new Date()
  const from = new Date(to.getTime() - 24 * 3600 * 1000)
  listPersonTracks(row.personId, {
    from: from.toISOString(),
    to: to.toISOString(),
    current: 1,
    size: 50
  }).then(res => {
    const page = unwrap(res) || {}
    tracks.value = page.records || []
  }).catch(() => { tracks.value = [] })
}

function onSiteChanged() {
  detailOpen.value = false
  getList()
}

onMounted(() => {
  getList()
  window.addEventListener('site-changed', onSiteChanged)
})
onUnmounted(() => window.removeEventListener('site-changed', onSiteChanged))
</script>

<style scoped>
.hint { color: #64748b; font-size: 13px; margin: 0 0 12px; }
.plot {
  position: relative;
  height: 180px;
  margin-bottom: 16px;
  border: 1px solid #dbe4ee;
  border-radius: 8px;
  background: linear-gradient(#f8fafc, #eef4f8);
  overflow: hidden;
}
.plot-dot {
  position: absolute;
  transform: translate(-50%, -50%);
  border: 0;
  background: transparent;
  color: #0f172a;
  font-size: 12px;
  cursor: pointer;
  white-space: nowrap;
}
.plot-dot::before {
  content: '';
  display: inline-block;
  width: 8px;
  height: 8px;
  margin-right: 4px;
  border-radius: 50%;
  background: #64748b;
}
.plot-dot.ok::before { background: #16a34a; }
.plot-dot.stale::before { background: #d97706; }
</style>
