# 历史测试与现行业务回归

本目录保存三端统一方案已取消流程的原测试内容，扩展名为 `.dart.txt`，不会被 `flutter test` 发现。迁移不是通过跳过失败来维持旧功能；当前产品不再提供交接班、独立巡检、成员编辑、第二轮审批或实验室视频流程。

| 原测试文件 | 归档原因 | 当前覆盖 |
| --- | --- | --- |
| wear_duty_management_test、wear_duty_reference_test | 交接班和接管入口已移除 | wear_app_test 检查入口隐藏及旧路由返回现场首页 |
| wear_inspection_test、wear_inspection_permissions_test | 独立巡检项和完成率已移除 | wear_phase_one_test、wear_work_reference_test 检查作业查看和事件记录 |
| wear_task_members_test、wear_task_completion_refresh_test | 作业来源只读，不允许安卓编辑成员或提交巡检完成 | wear_phase_one_test、wear_work_reference_test、wear_current_work_test |
| wear_event_close_dialog_test | 独立审批及旧关闭表单被共享最终核验替代 | wear_event_reference_test、wear_event_submit_feedback_test、wear_events_widget_test |
| wear_lab_auto_close_test、wear_lab_calls_test、wear_lab_compact_call_test、wear_lab_invite_test、wear_lab_video_source_test | 联调专用音视频入口隐藏，本轮不建设通话邀请和实时视频 | wear_comms_entry_test、wear_contact_actions_ui_test、wear_no_device_test；实际设备效果待实机 |

仍有效的通讯联系人、刷新、缓存与纯模型测试继续运行，复用数据已提取到 `test/wear_communications_fixture.dart`。现有辅助模块保留，不表示其隐藏的实验室页面进入本版范围。

## 当前默认命令

```powershell
& D:\AndroidDev\flutter\bin\flutter.bat test --dart-define=WEAR_MOCK=true --concurrency=4 --timeout=40s --reporter expanded
```

2026-10-07 本轮结果：**334 通过、0 失败、4 跳过**，日志在 `build/device-ready-final-tests.log`。

4 项跳过均为原有条件：`wear_contact_group_actions_test` 的 2 项实验室群呼、`wear_contact_presence_ui_test` 的 1 项实验室广播回执，以及 `wear_contact_preview_test` 未指定输出目录的 1 项截图任务。它们不计入当前业务通过数，也不代表真实语音、视频或广播已验收。

新业务回归覆盖现场补充与最终核验分离、网络失败保留输入、版本冲突、草稿重进、重复提交、多个 SOS、无设备求助、普通用户权限、字号变化和返回路径。真实模式不以 Mock 回归代替网络验收，另见仓库的三端待真实设备联调版验收说明。
