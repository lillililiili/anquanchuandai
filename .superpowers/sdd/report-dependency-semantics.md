# Guardian / 管理端依赖故障语义

提交：`8d79d55fac1eaa03753e9577ad3b3b64ae47fd1f`。

| 文件和方法 | 改动 |
| --- | --- |
| `WearableDependencyError.unavailable`、`GuardianError` | Guardian 与 admin 控制器（含实际 MVC 会话拦截阶段）的 Redis / DB 资源、超时及事务边界异常改为 HTTP 503，正文为 `code:503`、`errorCode:SERVICE_UNAVAILABLE` 和可读提示；不返回异常细节。原 Guardian 领域异常处理优先于依赖处理，两者均优先于旧 RuoYi 通用处理器，其他控制器仍沿用旧约定。 |
| PC 前台 `guardian-events.js:command` | 拒绝 HTTP 错误、旧 HTTP 200 错误体和无效回执；仅认可对应事件及有效版本，无法确认结果时同一操作保留稳定请求编号。有效回执足以确认写入，即使后续快照刷新未成功。 |
| PC 前台 `files.js:blobPut` | 只在服务器明确确认该文件 ID 时完成上传。错误或无效回执阻止后续关联照片及成功提示。 |
| PC 后台 `businessConfigApi.js`、`ClusterMaintenancePanel.vue` | 读状态、变更、核对均检查旧错误体及维护状态字段。请求失败时清空旧状态，展示错误并禁用状态依赖操作。 |

RED：MockMvc 复现 3 个依赖故障原本返回 HTTP 200 的场景；另有一个夹具账号需更正为真实系统管理员。PC 包装器和维护接口的新增测试分别因错误响应被当作成功而失败。

GREEN：MockMvc / 本地后端测试 42 项，PC 前台 236 项，PC 后台 487 项，全部通过。`git diff --cached --check` 通过。MockMvc 使用正式 Controller、拦截器、会话服务与两个错误处理器；覆盖会话 Redis 故障下没有进入上传、管理会话 DB 故障、业务快照超时、上传与维护成功形状、原 400/401 和旧 RuoYi 的 200 错误约定。PC 的组件级测试使用真实 EventView 提交流程与事件 API：旧 200 错误保持本地草稿并禁止成功提示，随后以同一请求编号提交成功。上传与维护 API 另覆盖错误体和无效回执。

日志：`D:/DevTools/dm8-tmp/dependency-red.log`、`dependency-green.log`、`dependency-pc-front.log`、`dependency-pc-admin.log`。没有重启服务或操作容器、真机和私有配置。真实依赖暂停/恢复、最终 JAR 与浏览器交互由主任务统一复验；本报告不声称这些已通过。
