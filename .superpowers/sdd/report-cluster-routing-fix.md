# stop_recording 清理投递 P1 修复报告

状态：本轮 P1 已修复且定向验证通过，等待独立复审。仅修复 `review-cluster-routing.md` 指出的停止录像业务阶段被内部 cleanup Pending 覆盖、原 HC 滞留 PREPARING 的问题。基线 `f99edd3a732fe01998968edfde25a4ce5a6b8094`。不扩展媒体全局协调、UI、部署或性能测试。

## 行为与实现

- cluster 模式停止录像在云端 DELETE 成功后保留 `finalizing`；取消未开始的录像保留 `completed`。
- 新的 `finishRecordingStop` 先保存已确认的业务阶段，再用原 HC 的 `talkback_id` 激活 `server_push_stop_rtsp`。不产生第二条 HT，业务记录与 transport 一对一关联。
- 清理 `Pending` 不改业务阶段。公开读回仍从原 HC transport 取得真实 `QUEUED/SENT/EXPIRED/ACKNOWLEDGED`；QUEUED 不声称已发送，SENT 不声称有录像文件。
- 有 viewer 或离线而无需发送时调用既有 `completeWithoutSend`，让 PREPARING 结束为 CANCELLED（无须发送的 transport 状态），业务可以继续 finalizing。
- activation 后不再保存先前的业务 row，改为 `commandState(id)` 读取最新业务结果，避免本次新收尾路径覆盖更晚的完成状态。云 recording ready 或 asset.ready 继续走原收敛逻辑更新同一 HC 为 completed。
- 保留现有单节点路径与现有回执协议；没有凭空增加 stop_rtsp ACK。回归中 transport ACK 使用既有 router 契约，后续媒体回执不能将 finalizing 降级。

## RED / GREEN 与验证

所有日志位于 `output/dm8-cluster/`，不包含私有连接配置内容。

| 检查 | 证据 |
| --- | --- |
| 定向 RED | `routing-fix-red.log`：19 项中 4 个预期断言失败；两条 finalizing 路径及取消 completed 被读回 requesting；有 viewer 的 HC delivery 为 QUEUED 而非结束 PREPARING |
| 定向 GREEN | `routing-fix-green.log`：53 项，0 failures / 0 errors / 0 skipped；含 ClusterMediaIntegrationTest 20、HelmetMediaServiceTest 32、HelmetMediaReceiptTimeTest 1 |
| DM8 原定向脚本 | `routing-fix-dm8.log`：32 项，0 failures / 0 errors / 0 skipped，BUILD SUCCESS |
| MySQL 原定向脚本 | `routing-fix-mysql.log`：32 项，0 failures / 0 errors / 0 skipped，BUILD SUCCESS |
| 静态检查 | 本次两个 Java 文件 `git diff --check` 通过 |

新增五项场景：

1. 已有录像、无 viewer：stop 保持 finalizing/QUEUED，owner dispatch 后 finalizing/SENT；云 GET recording ready 后，同键返回同一 HC completed 与 assetId。
2. 同样停止后，通过假云 `asset.ready` 完成；transport ACK 与设备媒体 report 不降级 finalizing，最终同键 completed。
3. 录像等待视频时取消：stop completed/QUEUED，源录像 cancelled；dispatch 后 completed/SENT，不再 POST recording。
4. 有 viewer 不发 stop_rtsp：HC transport 结束 PREPARING，云端随后仍可完成封装。
5. cleanup 投递过期：finalizing/EXPIRED 不被覆盖；云 ready 后 completed/EXPIRED，同键不创建新尝试。

断言同时检查业务 store、公开状态与 transport 状态、HC ID、transport 总行数 2（start + stop）、HT/PREPARING 行数 0、wire 的 talkback_id。正常路径只有 start 1 条和 stop 1 条，重复 dispatch 和同键重试不增加 wire；无 cleanup/已过期路径只有 start 1 条。

### 证据边界

新增录像场景使用真实 H2 JDBC `WearableBusinessStore` / `HelmetMediaStore` / router，gateway sender 与云端为 synthetic fixture。DM8/MySQL 脚本同时回归这些 H2 场景和 `RealClusterProcessTest`：后者确实连接隔离 WEARABLE_TEST / wearable_test，并启动真实独立 JVM、Spring、loopback WS/HTTP，验证原路由竞争及崩溃矩阵。**不把新增录像场景说成双节点真实媒体云验收。**

DM8 本轮进程证据：`D:/DevTools/dm8-tmp/cluster-process-15475558866372661557/evidence.json`，数据库产品 DM8，PID 65500 / 24748 / 47544 / 14864 / 65260；命令结果 UNKNOWN（before/after crash）、SENT（db-outage/durable）、ACKNOWLEDGED（early/one）、CANCELLED（same）。进程由原 fixture finally 清理。

MySQL 本轮进程证据：`D:/DevTools/dm8-tmp/cluster-process-1343336665232543175/evidence.json`，数据库产品 MYSQL，PID 43704 / 31360 / 11028 / 46040 / 2964；上述七条 transport 结果与 DM8 一致，进程由原 fixture finally 清理。

复跑使用既有 `ruoyi-admin/src/test/scripts/run-cluster-routing.ps1 -ConnectionFile <private JSON>`，JDK `D:/DevTools/jdk-17.0.20.1+1`，Maven `D:/DevTools/apache-maven-3.9.16/bin/mvn.cmd`，argLine `-Djdk.net.unixdomain.tmpdir=D:/DevTools/dm8-tmp -Djava.io.tmpdir=D:/DevTools/dm8-tmp`。DM8/MySQL 顺序执行，没有并发 Maven。

## 代码变更说明

| 文件/类 | 方法/函数 | 方法作用 | 本次修改的代码作用 |
| --- | --- | --- | --- |
| HelmetMediaService | command、finishRecordingStop（新增） | 处理停止录像与设备清理 | 原 HC 激活 cleanup，保存并保留业务 phase，结束无发送 admission，投递后只读最新业务 |
| ClusterMediaIntegrationTest | 五项 stop 回归、startRecording / stopInput / assertStopDelivery / assertStopWire；mediaSetup | 构建 SQL 媒体 fixture、捕获实际 sender wire 并断言 | 覆盖云 ready、asset、pending cancel、无须发送、expired；校验业务/transport/wire 关联与次数 |

## 保留边界

全局媒体副作用、维护/quiescent、跨节点业务条件更新及早回执覆盖等任务 2 工作保持原边界。本次没有泛改 receipt/saveCommand 或全媒体锁，不宣称解决所有早回执竞争。未接触真实设备、日常服务、WEARABLE_APP、父任务 deploy/benchmark/GuardianFiles；未执行 push/merge。未跑完整后端/前端/Android/browser；本次验证范围是上述定向测试与两数据库路由脚本。
