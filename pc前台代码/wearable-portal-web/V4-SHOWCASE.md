# 前台深蓝提亮与现场图片升级

## 后续调整：列表与地图联动

- 选中围栏时仅显示对应详情中的围栏，自动聚焦；未选择时可查看当前页围栏分布。
- 选中人员/设备时仅显示该对象的位置，不叠加无关联围栏；未知坐标仍不落点。
- 两个厂站的预置人员与围栏改为错列分散布局，矩形围栏互不重叠，轨迹继续以各人员位置为起点。
- 数据只在 Mock 种子中调整，刷新页面即可加载新分布。真实设备坐标不作改动。
- 检查脚本：`scripts/browser/selection-map.js`，涵盖连续选择、跨页选择及未知坐标。

本次仅修改 wearable-portal-web 前台，保留深蓝主题与原业务数据逻辑。

## 打开与演示

- 本地地址：http://127.0.0.1:5179/#/overview
- 启动：在本目录运行 `npm run dev:mock`。
- 预置负责人账号：`admin`，密码见 `src/mock/credentials.js`。
- 建议顺序：安全总览 → 人员装备 → 人员详情（生命体征与三类装备图片）→ 现场监看（位置 / 视频 / 轨迹 / 围栏）→ 作业监护 → 事件处置 → 查询分析。
- 预置业务数据在浏览器内运行，刷新重置；高德底图需要网络。图片为本地静态资源。
- 图片中的设备与人员为概念场景，页面有来源标注；静态图不代表设备实际在线、实时视频或事件证据。

## 修改范围

- 新增 `src/styles/v4-vivid.scss`：深蓝底色、提亮面板、青绿与暖金重点、导航与表格层次、响应式细节。
- 首页增加变电站主视觉与四个场景入口，保留原指标下钻、厂站隔离与事件入口。
- 视频播放器在未播放时显示场景图；设备条增加场景缩略图。真实媒体逻辑仍由原播放器负责。
- 资料列表增加带来源标记的示意封面；本地导入文件不以示意图冒充原文件。
- 装备详情及人员装备卡增加概念产品图。
- `VectorMap.vue` 接入高德 JS API 2.0，支持位置、轨迹、围栏、缩放及卫星图层；使用 WGS84 → GCJ-02 转换，分批、去重和缓存。网络或转换失败回退 `OfflineVectorMap.vue`，释放高德实例。
- 高德配置保存在已忽略的 `.env.local`，不在说明文档重复凭据。

## 图片交付

使用内置 image_gen 工具，每张图片单独生成。未使用 API/CLI 生成回退。
原始 PNG 保留在 `output/imagegen/originals/`；网页使用 `public/images/showcase/` 下 10 张 WebP，合计 2,062,022 字节。WebP 仅做编码转换，未改动图片构图。

| 文件 | 使用位置 |
| --- | --- |
| hero.webp | 登录、首页主视觉 |
| substation.webp | 巡检入口、视频与资料场景 |
| control-room.webp | 配电巡查入口、视频与资料场景 |
| height-work.webp | 高处作业入口、视频与资料场景 |
| team.webp | 班组交底入口、视频与资料场景 |
| equipment.webp | 装备概览 |
| helmet.webp | 安全帽装备卡 |
| harness.webp | 安全带装备卡 |
| watch.webp | 手表装备卡 |
| solar.webp | 视频与资料场景 |

## 生成提示词

### hero

Wide cinematic industrial photography for a dark navy blue safety monitoring dashboard hero banner. Modern Chinese electrical substation at vivid blue hour just before sunset, luminous cyan blue sky, warm golden sunlight, green landscaping, two engineers in blue workwear and white helmets on RIGHT, left negative space navy blue for heading. Bright clear energetic premium photography, no text logos. 16:9.

### substation

Realistic sunny daytime photograph of Chinese electric substation inspection, two Chinese workers blue uniforms white helmets inspecting transformer bays. Clear blue sky, green landscaping, bright fresh natural colors. Industrial demo still. Wide 16:9, no text logos overlays.

### control-room

Realistic bright modern power control room photograph. Chinese technician blue workwear white safety helmet checking pale gray electrical cabinets with blue accents, crisp daylight, premium documentary photography. Wide 16:9, no text logos overlays.

### height-work

Photorealistic utility maintenance scene, technician blue uniform white helmet wearing full body safety harness with secured lanyard working on elevated maintenance platform, Chinese substation green hills bright blue sky. Safe working posture, energetic natural photography. Wide 16:9, no text logos.

### team

Photorealistic morning pre-work safety briefing of four Chinese electrical workers in blue uniforms white safety helmets around a tablet, substation green trees bright warm daylight, natural faces candid premium photography. Wide 16:9, no logos text.

### equipment

Premium realistic product showcase on deep navy background with bright cyan rim lights. Smart white industrial helmet with compact black mounted camera, navy orange full body safety harness, rugged black smartwatch neatly arranged on low blue plinths. Crisp studio light, bright products, realistic materials. Wide 16:9 no text logos.

### helmet

Product photography, single white smart industrial safety helmet with black compact camera attached and chin strap, full product visible centered on blue plinth, rich navy backdrop cyan edge lighting, realistic crisp bright materials, square image, no text no logo.

### harness

Product photography, full body navy and bright orange industrial safety harness with metal buckles and dual lanyard, isolated hanging fully visible, premium deep navy studio with cyan lighting, high detail, square image, no people no text no logo.

### watch

Product photography, rugged black industrial smartwatch with teal screen showing simple heartbeat waveform without text, black strap fully visible curved upright, deep blue plinth navy studio cyan edge lighting, crisp detailed realistic square image no logos.

### solar

Photorealistic modern Chinese solar power plant inspection, engineers blue workwear and white helmets walking among blue photovoltaic panels, clear sky green hills, vibrant fresh daylight premium photography. Landscape 16:9 no text no logo.

## 验证

- ESLint 检查通过；168 项单元测试通过（含新增坐标转换批次、缓存与失败重试测试）。
- `build:mock` 与 `build:prod` 均构建通过。
- 13 个页面/标签的浏览器巡检，无脚本错误、无图片加载失败；首页覆盖 1366 / 1024 / 768 / 390 像素宽度。
- 浏览器检查脚本：`scripts/browser/v4-showcase.js`；结果：`output/v4-browser-results.txt`；截图：`output/playwright/v4-*.png`。
- 交互验证通过：20 个位置标记（含选中标记）、25 个围栏，地图自动适配、放大、卫星图层切换；8 路图片分屏；25 人指标下钻。结果：`output/v4-interactions.txt`。
- 小屏额外检查了内部工作区宽度，390px 下主内容 `clientWidth = scrollWidth = 303px`。
- 地图接入参考：[高德 JS API 安全密钥](https://lbs.amap.com/api/javascript-api-v2/guide/abc/jscode)、[地图状态与视野](https://lbs.amap.com/api/javascript-api-v2/guide/map/state)。


## 人员定位列表调整

定位页以人员名册分页，人员下展示安全帽、安全带、智能手表的领用状态，已领用设备显示编号。无定位人员仍保留，未领用、未知和冲突单独标识。位置仅采用同厂站、人员归属已确认且仍在该人员已领用设备中的快照；点击人员仅展示其定位，没有确认位置时清空地图点并禁用轨迹入口。搜索和分页均按人员。

验证：171 项单元测试通过、lint 通过、mock 构建通过；浏览器检查三类领用设备、人员筛选、分页、单点切换、无定位状态及 390px 无横向溢出通过。截图：`output/playwright/person-location-issued.png`。
