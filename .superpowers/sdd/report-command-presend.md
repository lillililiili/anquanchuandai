# 命令发送前终态修复

首轮提交 `77886d75c8238f8058dde0c9080642c10d44e510`，评审补充提交 `8dff7be68e3e874d528e050f55f99f475ad6ab74`。

| 文件和方法 | 职责和改动 |
| --- | --- |
| `DeviceCommandRouter.dispatch`、`finishBeforeSend` | 持久化尝试认领后复核节点、权限、设备连接和命令租约。复核异常且尚未调用发送器时，同一认领的 `DISPATCHING` 或恢复所得 `UNKNOWN` 可结案为 `FAILED_BEFORE_SEND`，包括原认领已过期的情况。已有设备确认、不同认领和其他终态受到更新条件保护。一旦进入发送器，继续使用原先的有效尝试租约条件，异常保留 `UNKNOWN`。 |
| `ClusterRoutingContractTest.maintenanceAfterDurableClaimFinishesBeforeSend` | 使用 H2 和正式维护守卫，在第二次检查时确认另一数据库连接已看到认领，再分别开始节点排空、全局暂停。另覆盖认领过期，以及恢复任务已将同一认领标记为未知的情况。验证发送次数为零、恢复后仍为失败终态，且相应协调状态报告 `uncertainTransport=0` 和 `quiescent=true`。 |
| `ClusterRoutingContractTest.senderFailureRemainsUnknownAndNeverRetries` | 发送器抛出 I/O 异常后连续运行两次分发，验证发送器仅调用一次且仍为 `UNKNOWN`。既有过期认领测试继续覆盖崩溃后结果未知。 |

RED 运行 14 项，两个新增维护场景均出现预期的状态断言差异（实际 `UNKNOWN`）。GREEN 运行 43 项，全部通过。测试类为 `ClusterRoutingContractTest`（14）、`ClusterMediaIntegrationTest`（25）、`ClusterControlControllerTest`（4）。`git diff --check` 通过。

日志位于 `D:/DevTools/dm8-tmp/command-presend-red.log` 和 `D:/DevTools/dm8-tmp/command-presend-green.log`。使用 JDK 17、Maven 3.9.16，Maven 和 Surefire JVM 均限制为 512 MiB，ASCII 临时目录。真实 DM8、MySQL 和容器运行时未参与此轮验证，最终制品由主任务统一构建。

过期认领补充验证 RED 共 16 项，过期与恢复先行两个场景均出现预期的状态断言差异。GREEN 共 47 项全部通过，覆盖上述三个测试类（16、27、4），`git diff --check` 通过。日志为同目录下 `command-presend-expiry-red.log` 和 `command-presend-expiry-green.log`。
