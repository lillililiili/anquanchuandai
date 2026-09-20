const root = `${import.meta.env.BASE_URL}images/showcase/`
export const scenes = [
  { id: 'substation', title: '变电站巡检', description: '人员定位 · 现场监看', path: '/video', image: root + 'substation.webp' },
  { id: 'height-work', title: '高处作业监护', description: '安全穿戴 · 作业协同', path: '/supervision', image: root + 'height-work.webp' },
  { id: 'control-room', title: '配电设备巡查', description: '现场影像 · 资料留存', path: '/materials', image: root + 'control-room.webp' },
  { id: 'team', title: '班组安全交底', description: '当班人员 · 调度协同', path: '/dispatch', image: root + 'team.webp' },
]
export const showcaseImage = name => root + name + '.webp'
const previewScenes = [...scenes, { id: 'solar', title: '光伏场站巡检', image: root + 'solar.webp' }]
export function sceneFor(value = '') {
  const hash = [...String(value)].reduce((sum, char) => sum + char.charCodeAt(0), 0)
  return previewScenes[hash % previewScenes.length]
}
