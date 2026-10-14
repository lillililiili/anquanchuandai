# Sketch UI 规范

两端共用本目录；页面布局仍由各自项目维护。

- `source-manifest.json`：唯一源文件摘要、28 个规范/图标分组、8 张业务画板、字体摘要。
- `tokens.css`：53 项原稿颜色；透明度独立保留。
- `controls.css`：字体及公共交互组件样式。
- `component-mapping.md`、`component-mapping.json`：组件采用规则与原稿图层、尺寸、填充、边框、圆角对应关系。
- `icon-mapping.csv`：业务名称、原稿名称、图层路径、矢量源摘要和语义适配说明。
- `icons.json`、`UiIcon.vue`：直接导出的矢量路径、变换、裁剪和透明度；每个实例独立裁剪 ID。
- `evidence/`：全部可见规范图层、控件测量、53 项色板、完整图标目录和原稿矢量预览。
- `fonts/`：Sketch 内嵌思源黑体原文件；英文、数字优先 Arial。

开发验收页：前台 `http://127.0.0.1:5191/ui-spec.html`，后台 `http://127.0.0.1:5181/ui-spec.html`。它们不进入默认生产构建。验收页数据仅保存在组件内存中，不调用业务写接口。

公共组件通过 `install.js` 注册。选择器支持单选、多选、动态选项、禁用、必填、键盘及原生表单校验；日期支持本地日期/日期时间字符串、年月切换、清空、上下限及键盘操作。浮层自动寻找原生 `dialog`，处理窗口边缘、滚动、外部点击、Tab 和 Escape；Escape 先关闭最上层浮层并返回焦点。

可重复执行的抽取流程（仓库根目录）：

```powershell
python -X utf8 scripts/extract-ui-spec.py 'D:/wx_chat/xwechat_files/wxid_x9ztlatrmfbm22_4b89/msg/file/2026-10/UI规范.sketch'
python -X utf8 scripts/extract-ui-reference.py
python -X utf8 scripts/document-ui-spec.py
```

源文件 SHA-256 必须匹配清单。`migrate-ui-spec.py`、`normalize-ui-colors.py` 是本次迁移使用的一次性脚本，不应对已迁移代码重复执行。

本次适配：原稿没有直接对应的业务图标时选用同库语义最接近项，逐项列在 CSV；监控大屏指标数字字号和 1672×941 画布比例保留。品牌、照片、地图及视频资源沿用现有系统。

Windows 环境没有 macOS Sketch 原生渲染器。验收页的原稿预览来自原始图层路径和属性导出，不标作 Sketch 原生截图。颜色/alpha、几何参数和矢量来源可逐项追溯；浏览器验收记录与前后截图见仓库根目录 `design-qa.md` 和 `output/ui-spec/`。
