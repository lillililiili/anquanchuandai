# 前台业务画板主题

本轮范围为前台 16 个业务页面和独立数据大屏。登录页、管理后台、接口、路由、业务数据模型以及共用控件的默认行为均未修改。主题通过前台根节点的 `data-portal-theme` / `data-portal-family` 作用于业务页及其浮层，离开业务页时清除。

## 原稿和提取

- 原文件：`D:/wx_chat/xwechat_files/wxid_x9ztlatrmfbm22_4b89/msg/file/2026-10/UI规范.sketch`。
- SHA-256：`20ee13bff161045011c20cb5c4fda6d8128a6e74c97d8dec7c61f378d137c36f`。
- [business-layers.json](business-layers.json)：8 张业务画板的 8,361 个可见图层，包含 ID、层级、相对坐标、全部 style、字体、文本属性、圆角和图片引用。隐藏层不进入导出，文字说明不作为页面内容。
- [references.json](references.json)：画板 ID、尺寸与开发环境参考文件。
- [assets.json](assets.json)：7 个生产 SVG 的原始图层 ID、文件摘要、4 张背景图片的原始摘要及无损传输编码摘要。
- [renderer-notes.json](renderer-notes.json)：重建限制。SVG 参考页不是 Sketch 原生渲染，不能据此宣称逐像素一致。
- 复现：仓库根目录运行 `python scripts/extract-portal-design.py`，需要 Python / Pillow；原 Sketch 必须存在且摘要一致。

参考页在 `pc前台项目/ui-reference/`，开发地址 `/ui-reference/reference-1.html` 至 `reference-8.html`。它们和原始图片不进入默认生产构建。生产装饰位于 `pc前台项目/public/assets/sketch/`。

导出保留原矢量路径、变换、启用的填充、渐变、遮罩和透明度。背景位图仅做 WebP 无损传输编码，每张都对解码后的 RGBA 字节作相等断言；保留原分辨率，不裁小、不降质。修正裁剪与变换后的背景 SVG 为 16,987,717 字节。没有生成新图片，也没有把原稿装饰替换为手绘图形。

2026-10-14 背景复查：此前 `clipPath` 内误用了 `<g>` 包装，Chromium 将其视为空裁剪区，导致原稿位图实际上未显示。现将变换直接放在裁剪几何上，重新导出全部素材和参考页；原始图层、图片、透明度均未改变。背景资源与实际业务组件叠加已在三种验收尺寸复查，详见 [补充记录](../../../output/portal-background-fix/README.md)。此前全量业务截图中的背景不是修复后的效果。

同日继续修复背景分界线：顶部遮罩 `15F83B84-63FF-4987-9D25-5618C2DA880E` 同时旋转 90°、垂直翻转，旧导出变换使其在内侧形成深色硬边。导出改为围绕中心旋转后沿父坐标轴翻转，透明端位于内侧 y=190，深色端朝页面顶部；底部遮罩保持向底边加深。源位图、渐变 stops 与 alpha 没有修改。业务页根背景与固定页头统一使用 viewport/cover，body 不再发生 110px 顶部外边距折叠；大屏也使用 cover，保留画布比例。通过 `python scripts/test-portal-background.py` 运行 3 项源参数回归。[当前浏览器实测记录](../../../output/portal-background-seam/README.md)。

## 页面与画板映射

|前台路由|视觉类别|主要参考画板|
|---|---|---|
|overview|monitor|监盘总览|
|personnel|list|巡视点位|
|person/:id|detail|工作票、缺陷单处理|
|works|list|巡视点位、告警及检修建议|
|work/:id|detail|工作票|
|video|sentinel|安全哨兵、监盘总览|
|single/:id|sentinel|安全哨兵|
|materials|list|巡视点位|
|location|sentinel|安全哨兵、监盘总览|
|tracks/:id|sentinel|安全哨兵、监盘总览|
|fences|sentinel|安全哨兵，表单缺失状态引用组件库|
|alarms|list|告警及检修建议|
|event/:id|detail|缺陷单处理、告警弹窗|
|dispatch|sentinel|安全哨兵|
|sos|sentinel|安全哨兵、告警弹窗|
|statistics|monitor|巡视报告、监盘总览|
|screen|sentinel|安全哨兵、监盘总览；保留独立画布|

画板中的特定视觉参数优先；未覆盖的状态使用既有 [组件映射](../component-mapping.md) 和 [颜色证据](../evidence/colors.json)。同类业务内容不照搬原稿文字或业务功能。

## 关键参数及来源

|对象|采用参数|原稿 ID / 证据|
|---|---|---|
|导航主体|70px；标题框 522px；菜单 20px/23.4px，Medium，字距 1px|`41C718E0-27EF-48AB-9240-CBCF77F2041D`|
|居中标题|30px/36px，内嵌 Heavy，字距 3.72px；白色 32.781915% → #A3E4FF 85.094658%|`1D97CB1D-8D2E-4C0F-B03F-07B7D44B95ED`|
|导航装饰、选中/默认底图|原路径和填充导出；文字使用现有业务名称|`assets.json` 中逐项 ID|
|业务背景|原稿四张位图叠层及裁剪；页面基础色 #121E37|`3197994C-12B8-437E-855E-893B62166CA5`|
|列表卡片|rgba(80.40707499,177.28612930,248.56881469,.08)，6px 圆角；1px 内描边 rgb(0,75.50417253,124.20855978)|`AE428F6E-D09A-4F46-97DC-E15D1D7C8D14`、`C48A4D03-5851-45D6-B439-0B23A5723800`|
|监盘/安全哨兵面板|rgba(15.936373,30.65213,48.043478,.2192963287)，5px 圆角；内阴影 inset 0 0 49px -2px rgba(94,203,255,.152808129370629)|`DA54D277-549F-49FE-BEE1-176306059EF1`、`FB97B87B-0DFC-47BC-B8E7-31B0EAC6DBA6`|
|详情卡片|原长表单 12px 圆角、12% 蓝色填充|工作票、缺陷单处理及既有组件映射|
|面板标题装饰|216×25，16px 标题、#32C5FF|`67A52F67-DEAE-4ACB-9801-70CE6BB99902`|
|业务列表表头|垂直 #5ECBFF 渐变，alpha .1 → .3，终点 99.6175699300699%|`B331553C-B1E4-4B30-8DD0-ECFFEF58298C`、`9E7685A3-A5FC-4EC7-933D-1A1829DC99D5`、`1BE3A946-32E8-4A68-A997-294FDF390D3A`|
|间隔行|#CCDEFF alpha .05；另一行透明；54.702995px 单行基准|`0B88237F-AF20-4ED8-AA1F-E4A93D76FF7B`、`01DD6653-1FA5-446C-9789-4EE412DA0D98`|
|筛选按钮|96×35，4px 圆角，16px，原稿双层描边背景；普通表单 32、行内操作 24|`6B237A78-EF80-44D0-964B-971401C13790`，字层 `9DE0191D-E6AD-49E6-A804-6F05BE4D0FC2`|
|字体|内嵌思源黑体 400/500/700/900；英文数字优先 Arial|`../fonts/`、`../source-manifest.json`|

表头必须读取启用填充的 `fillType=1` 和 gradient stops，不能使用其遗留的 `color=#CCDEFF/.15` 字段；也不能在 thead 与 th 重复叠加半透明背景。

## 图标、素材和适配

沿用 [130 个业务别名 → 90 个原稿矢量的映射](../icon-mapping.csv)。本轮没有引入额外图标库，更多箭头仍用原稿 `chevron-down`；大屏指标使用原稿 worker/document/antenna/warning 等语义映射，移除了旧手绘六边形外框。品牌、设备照片、卫星地图、人员示意、现场视频和动态图表是原有业务内容，予以保留。

明确的布局适配：九项既有菜单保持原序（前四左、后五右），使用测量宽度将尾部连续项收入“更多”；新增 40px 工具条；移除 202px 全局侧栏占位，内部分栏关系不变。1920px 下显示九项，1440/1366px 下保留前三项，其余在“更多”；原稿菜单字不缩小。

原稿没有现有人员装备多行单元格与副标题；保留其内容和内部组合，允许行高超过单行基准，使用 14px/22px 以免截断。大屏仍为 1672×941 等比例画布，专用指标数字尺寸与地图标签定位逻辑保持原样；标题/面板/装饰按本次源参数应用。工具条、溢出菜单、业务照片以及这些内容密度适配不作为原稿逐像素复刻对象。

原稿少量按钮文字声明 PingFangSC，但文件内嵌字体为思源黑体；按已确认的内嵌字体规则，以 Source Han Regular 显示这些 16px 标签，未下载或伪造苹方。常用表头按源 Bold/14px/白色，正文 Regular/14px/白色，辅助内容与状态使用对应组件色。

## 验收入口

- [实际业务组件和状态](http://127.0.0.1:5191/portal-spec.html)，使用内存状态，不调用业务 API；32/35/24px 控件、渐变表格、多选、禁用、日期、必填与弹窗。
- [完整公共组件状态](http://127.0.0.1:5191/ui-spec.html)。
- [前后截图画廊](../../../output/portal-redesign/index.html)；[项目验收报告](../../../design-qa.md)。

默认生产构建只使用原来的 index.html；验收 HTML、参考 HTML 和参考位图不进入 dist。CSS 分为框架 `portal-shell.css` 与业务视觉 `portal-business.css`，页面自身的业务布局文件继续管理分栏。

## 2026-10-14 全页复查补充

[本轮复查报告](../../../output/portal-ui-audit-20261014/README.md)和[最新前后截图](../../../output/portal-ui-audit-20261014/index.html)优先于此前背景修复前的截图。补齐了上述启用内描边/内阴影；表格正文明确为 14/22px，筛选 35px；取消旧规则对页签及媒体选中态的覆盖。

下拉选中背景 `DWy8t7mnGQVDKRWwbjGpe` 使用 #83F6FD/20%，文字 `OeDUPEoekP_gtuY42NjP1` 使用 #83F6FD，键盘 active 不再覆盖选中填充。原稿非选中悬停采用亮青底白字；本轮根据用户对不合理细节的整改要求，将悬停文字改成规范深色以提高可读性，属于明确适配。长标题/设备元数据自然展开、筛选按钮整组换行、定位侧栏 365px 和作业表格姓名不拆行也是业务内容适配。大屏专用指标字号与区域人数逻辑保持现状。
