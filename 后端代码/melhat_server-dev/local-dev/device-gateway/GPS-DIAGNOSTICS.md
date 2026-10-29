# 临时定位诊断

默认关闭。由操作人员安全切换网关进程时，在当前 PowerShell 设置
`$env:HELMET_GPS_DIAGNOSTICS='1'`，再按原方式运行 `node cli.mjs`。
本次代码变更不会启动或重启网关。关闭该环境变量后，新进程恢复默认行为。

仅向 ignored 的 `.local/gps-report-diagnostics.jsonl` 追加最多 12 条记录；
已有记录计入上限，重启不增加额度。文件不写精确经纬度、设备身份、路径令牌或原始报文。
记录 UTC 接收时间、白名单数字质量字段、每个坐标的存在/有限/非零/范围布尔标志，
以及与同连接上一条坐标是否变化。第一条或无法比较时 `coordinatesChanged=null`。

`upstreamAck` 是后端 `cmd=ca_report_location` 的布尔 `status`；
`upstreamAckReceived=false` 表示未观察到能明确对应的 ACK，并非后端明确拒绝。
若后端返回不含原始动作的 `cmd=error`，停止该连接的后续诊断并将待匹配项记为未确认，避免下一条 ACK 错配。
报告与 ACK 按同一连接顺序关联，诊断回调或文件失败不改变原报文转发。
如需再次采集，由操作人员先归档旧诊断文件再启用，不会自动删除旧证据。

隔离测试：`node --test test/*.test.mjs`。测试 upstream 使用临时 loopback 端口，不连接日常后端。
