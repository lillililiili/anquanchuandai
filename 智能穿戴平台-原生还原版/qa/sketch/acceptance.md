# Sketch 参数校正验收

日期：2026-10-10。范围：修订用户桌面`data`中的个人UI技能，并精修本原生项目的样式；保留原导航、分栏、模块顺序和交互流程。

## 本轮结果

- `css/theme-tokens.css`收录原Sketch颜色表全部53行，分别保存用途、RGB、alpha和原图层ID。源值核对[53/53通过](token-validation.json)。
- 校正输入框透明底、32px高、4px圆角及青色默认/悬停/2px聚焦；复选框和单选框16px；下拉选项底色`#2E6086`。
- 面板、表格、边框、分割线和标签保留原稿透明度。标签采用26px常规规格及22px密集规格；圆角按组件类别选择。危险按钮、链接和主按钮状态统一。
- 固定壳层与浮层组合页面底色和原始半透表面，避免底层文字透穿；大屏保留原画布、指标尺寸、Arial数字、缩放与轮播。
- 本轮产品变更限于三份主题CSS与入口加载顺序；未修改业务JavaScript、路由、API、数据模型、事件绑定或存储键。项目适配和源稿事实见[STYLE.md](../../STYLE.md)。

## Skill 已更新

已把9个经过审阅的文件同步到`C:/Users/19221/Desktop/data`，逐文件核对写入哈希。修正了历史提示词中未证实的颜色、Roboto、输入2px圆角、14px选择框、双主题映射、全局圆角/字号限制，以及日期/进度条说明的误读。

原始A/B提示词及来源副本保持字节不变，旧合并提示词完整归档。五份被替换的旧文件另外保存在[同步前备份](skill-update/before-data)，本轮修订版也保留[项目内副本](skill-update/data/personal-ui-framework/SKILL.md)。同步清单见[sync-manifest.json](skill-update/sync-manifest.json)。没有全局安装技能或改动其他项目。

校验工具`quick_validate.py`已用本机Python3.11/PyYAML实际运行通过，桌面同步后再次通过。35处相对引用、243个证据图层ID、166处文档ID及53行原色均核对通过。独立试用检查确认：技能会保留64px顶栏、202px侧栏、40px登录按钮及现有大屏指标，不额外生成浅色主题或Starter。试用发现的两处文字歧义已修正。

## 页面、状态和业务检查

| 检查 | 最终结果 |
| --- | --- |
| `npm test` | 27/27通过 |
| `npm run check` | 六份业务JS语法检查通过 |
| `git diff --check` | 通过 |
| 页面与布局 | 18页×3分辨率，共54/54通过；无新增横向溢出、按钮裁切或壳层几何变化 |
| 组件状态 | 15组、54项断言全部通过；含RGB/alpha、输入状态、表格、面板、链接、危险按钮及大屏字体 |
| 登录及四条业务流程 | 5个独立场景、45项断言通过 |
| 既有大屏脚本 | 28项检查通过 |
| 既有通话视频脚本 | 单/群呼预览、接通、静音、循环、结束、取消和资源释放通过 |
| 静态视觉复核 | 全18页和2弹窗；无新增遮挡、裁切、按钮换行、透底干扰或数字错位 |

分辨率：1672×941、1366×768、1920×1080。浏览器检查均使用独立临时上下文，不修改用户浏览器的业务记录；最终页面/组件场景无脚本错误或资源失败。

检查过程中曾因并行浏览器占用内存而中断，最终改为串行运行。流程脚本还修复了两处测试同步问题：hash地址变化后等待目标DOM完成渲染再断言，未修改业务或降低断言要求。一次通话播放等待超时未能复现；[隔离诊断](call-video-diagnostics.json)及最终整套回归均通过，未据此修改媒体逻辑。

## 交付与复验

- [全部页面前后对比](index.html)：左侧是上一版，右侧是本轮Sketch参数校正后的版本。
- 代表对比：[总览](comparison-overview.png)、[人员列表](comparison-personnel.png)、[人员详情](comparison-person-P1.png)、[围栏](comparison-fences.png)、[大屏](comparison-screen.png)。
- 原始数据：[页面检查](after/inventory.json)、[组件状态](states/results.json)、[流程回归](flows/results.json)、[视觉复核](inspection/visual-review.md)。
- [修正前参数核验](reference/comparison.html)保留上一版与原稿/旧Skill的对照，用于解释修改原因；不代表当前实现仍使用其中的旧值。

在项目根目录的PowerShell中设置`$env:THEME_QA_DIR='qa/sketch'`，串行运行`node scripts/check-theme.cjs after`、`node scripts/check-theme-states.cjs`及`node scripts/check-theme-flows.cjs`。不要在修改后重建`before`基线。

原生选择框、复选框、日期面板保留浏览器行为，系统弹出外观可能因浏览器而异。原地图、媒体和人物素材继续使用现有项目资源；这是按源参数精修现有系统，并非复制Sketch全部业务画板或逐像素重建。
