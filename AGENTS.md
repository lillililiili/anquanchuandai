# 项目协作约定

- 本项目使用 `.agents/skills/` 中的 Matt Pocock Skills；按任务需要读取，用户明确调用的技能按其入口执行。停止使用 Superpowers，历史文档中的 Superpowers 流程不再作为执行要求。
- 安卓整改以客户《新版安卓端开发/智能穿戴管理平台-整体设计方案.docx》及用户指定预览图为依据。小步调整，保持既有风格与功能；未经要求不重新设计整体布局，不恢复亮暗切换。
- 已有接口继续正确对接；缺失接口允许展示明确的模拟数据，不能将模拟结果说成真实执行成功。
- 页面验收覆盖顶部、底部和父子页面跳转；保留底部导航栏、Logo 和通用按钮比例。用户要求部署时使用雷电模拟器；后端使用 Docker。

## Agent skills

任务与规格继续放在 `新版安卓端开发/开发任务拆分/`，沿用原有编号、总览和进度。使用任务管理技能前读取 `docs/agents/issue-tracker.md`；使用 triage 时读取 `docs/agents/triage-labels.md`；读取需求、术语或架构时参考 `docs/agents/domain.md`。
