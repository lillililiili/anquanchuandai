"""One-time migration for the approved 2026-09-06 wallboard refinement."""
from pathlib import Path
import re

p = Path('src/views/big-screen/index.vue')
s = p.read_text(encoding='utf-8')
assert '<style scoped lang="scss">' in s, 'Migration already applied'
s = re.sub(r'<style scoped lang="scss">[\s\S]*?</style>', '<style lang="scss" scoped src="./screen.scss"></style>', s)
s = re.sub(r'\s*<div class="corner-(?:top-right|bottom-left)"></div>', '', s)
s = s.replace('<div class="big-screen">', '<div ref="screenRoot" class="big-screen">')
s = s.replace('<div class="screen-card">', '<div class="screen-card overview-card">', 1)
for title in ['组呼对讲', '单呼对讲', '群呼对讲']:
    marker = '<!-- ' + {'组呼对讲':'左侧下部：组呼对讲','单呼对讲':'右侧上部：单呼对讲','群呼对讲':'右侧下部：群呼对讲'}[title] + ' -->'
    s = s.replace(marker+'\n        <div class="screen-card">', marker+'\n        <div class="screen-card communication-card">')
s = re.sub(r'\s*<div class="map-controls">[\s\S]*?</div>', '', s, count=1)
s = s.replace('class="alarm-item alarm-level-high"', 'class="alarm-item" :class="`alarm-level-${item.level}`"')
s = s.replace('<div class="group-avatar" :style="{ background: item.color }">', '<div class="group-avatar">')
s = s.replace('<div class="group-name">{{ item.name }}</div>', '<div class="group-name" :title="item.name">{{ item.name }}</div>')
s = s.replace('>{{ item.userName }}</div>', '><span class="person-label" :title="item.userName || item.deviceNo">{{ item.userName || item.deviceNo || \'未绑定设备\' }}</span></div>')
s = s.replace('<div class="single-group">', '<div class="single-group" :title="`${item.group || \'未分组\'} | ${callStatusMap[item.deviceNo] || item.status}`">')
s = s.replace('{{ item.group }} |', "{{ item.group || '未分组' }} |")
s = s.replace('class="broadcast-item">', 'class="broadcast-item" :class="{ \'is-selected\': selectedDeviceNos.includes(item.deviceNo) }">')
for ref, title, key in [('alarmStatsRef','告警趋势','alarm'),('intercomStatsRef','对讲统计','intercom'),('ttsStatsRef','广播统计','tts')]:
    s = s.replace(f'<div ref="{ref}" class="stats-chart"></div>', f'''<section v-loading="chartLoading.{key}" class="chart-panel" aria-label="{title}">
              <h2>{title}</h2>
              <div ref="{ref}" class="stats-chart"></div>
              <p v-if="chartErrors.{key}" class="panel-empty chart-error">统计暂不可用</p>
            </section>''')
for css, key, array, empty in [('alarm','alarms','alarmList','暂无待处理告警'),('group','groups','groupList','暂无作业群组'),('single','people','singleList','暂无可用设备'),('broadcast','people','broadcastList','暂无可用设备')]:
    s = s.replace(f'<div class="{css}-list">', f'''<div v-loading="panelLoading.{key}" class="{css}-list">
              <div v-if="!panelLoading.{key} && {array}.length === 0" class="panel-empty">{{{{ panelErrors.{key} ? '数据暂不可用' : '{empty}' }}}}</div>''')
s = s.replace("import { fromLonLat } from 'ol/proj'\n", '')
s = s.replace("import autofit from 'autofit.js'\n", '')
s = s.replace("const router = useRouter()", """const router = useRouter()
const screenRoot = ref(null)
const panelLoading = ref({ alarms: true, groups: true, people: true })
const panelErrors = ref({ alarms: false, groups: false, people: false })
const chartLoading = ref({ alarm: true, intercom: true, tts: true })
const chartErrors = ref({ alarm: false, intercom: false, tts: false })
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
let layoutObserver = null
let layoutFrame = null
let mapTimer = null
let markerTimer = null
function resizePanels() {
  cancelAnimationFrame(layoutFrame)
  layoutFrame = requestAnimationFrame(() => {
    resizeAlarmStats(); resizeIntercomStats(); resizeTtsStats()
    mapUtils?.map?.value?.updateSize()
  })
}""")
for fun, key, end in [('loadAlarmList','alarms','// ===== 组呼'),('loadHelmetList','people','// 加载全部'),('loadGroupList','groups','function getGroupColor')]:
    start = s.index(f'function {fun}()')
    stop = s.index(end, start)
    block = s[start:stop]
    pos = block.rfind('  })')
    assert pos >= 0
    block = block[:pos] + f"  }}).catch(() => {{ panelErrors.value.{key} = true }}).finally(() => {{ panelLoading.value.{key} = false }})" + block[pos+4:]
    s = s[:start]+block+s[stop:]
s = s.replace("const { setOptions: setAlarmStatsOptions }", "const { setOptions: setAlarmStatsOptions, resize: resizeAlarmStats }")
s = s.replace("const { setOptions: setIntercomStatsOptions }", "const { setOptions: setIntercomStatsOptions, resize: resizeIntercomStats }")
s = s.replace("const { setOptions: setTtsStatsOptions }", "const { setOptions: setTtsStatsOptions, resize: resizeTtsStats }")
s = s.replace("const tooltipStyle = {", "const tooltipStyle = { confine: true,")
s = s.replace("fontSize: 10 }", "fontSize: 11 }")
s = s.replace("legend: { type: 'scroll', top: 12", "legend: { tooltip: { show: true }, type: 'scroll', top: 4")
s = s.replace("top: 52, bottom: 16", "top: 38, bottom: 8")
s = s.replace("tooltip: { trigger: 'axis', ...tooltipStyle },", "animation: !reducedMotion,\n      tooltip: { trigger: 'axis', ...tooltipStyle },")
for key, start_marker, end_marker in [('alarm','  // 告警统计','  // 对讲统计'),('intercom','  // 对讲统计','  // 语音合成统计'),('tts','  // 语音合成统计','\nfunction initCharts')]:
    start = s.index(start_marker, s.index('function loadChartStats'))
    stop = s.index(end_marker, start)
    block = s[start:stop]
    pos = block.rfind('  })')
    assert pos >= 0
    block = block[:pos] + f"  }}).catch(() => {{ chartErrors.value.{key} = true }}).finally(() => {{ chartLoading.value.{key} = false }})" + block[pos+4:]
    s = s[:start]+block+s[stop:]
s = s.replace('  setTimeout(() => {\n    const utils = useMap()', '  mapTimer = setTimeout(() => {\n    const utils = useMap()')
s = s.replace('    mapInstance = utils.initMap(mapContainer.value)', '    utils.initMap(mapContainer.value)\n    mapInstance = utils.map.value')
s = s.replace('    setTimeout(() => {\n      // 添加人员标记', '    markerTimer = setTimeout(() => {\n      // 添加人员标记')
start = s.index('  // 添加全局样式重置', s.index('onMounted(() =>'))
stop = s.index('  updateTime()', start)
s = s[:start]+s[stop:]
s = s.replace('    initMap()\n  })', '''    initMap()
    layoutObserver = new ResizeObserver(resizePanels)
    ;[mapContainer.value, alarmStatsRef.value, intercomStatsRef.value, ttsStatsRef.value].forEach(el => {
      if (el) layoutObserver.observe(el)
    })
  })''')
s = s.replace("  autofit.off()\n", '')
s = s.replace("  if (timer) clearInterval(timer)", "  if (timer) clearInterval(timer)\n  clearTimeout(mapTimer)\n  clearTimeout(markerTimer)\n  layoutObserver?.disconnect()\n  cancelAnimationFrame(layoutFrame)")
s = s.replace("  // 移除全局样式\n  const style = document.getElementById('big-screen-global-style')\n  if (style) style.remove()\n", '')
s = s.replace('  loadHelmetAllList().then(() => {\n    loadGroupList()\n  })', "  loadHelmetAllList().catch(() => {}).finally(() => { loadGroupList() })")
p.write_text(s, encoding='utf-8')
print('Refined wallboard template, scoped stylesheet, loading states and container resize handling')
