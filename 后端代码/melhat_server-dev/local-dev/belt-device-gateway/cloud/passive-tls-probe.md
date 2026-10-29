# 有限时长被动网络诊断

`passive_tls_probe.py` 只在 Linux 服务器上以 root 运行。它不发送网络请求，不改变防火墙、Caddy、SSH 或设备配置，不安装软件。优先使用已有 `tcpdump`，其次已有 `tshark`；均不存在才使用 Python 标准库的 AF_PACKET。捕获工具的 pcap stdout 直接进入内存解析器，不写 pcap 文件。原始 IP、SNI 名称、URL、路径凭据、HTTP 内容及原始报文不会进入输出。HTTP 只计连接，不解析或缓冲内容。

由操作者上传脚本后，在约定的设备重启观察窗口内手动运行一次：

```sh
python3 -B /root/belt-deploy/passive_tls_probe.py --seconds 45 --backend tcpdump
```

`--seconds` 只允许 1–60；为捕获子进程退出预留时间，实际捕获最多 58 秒，子进程结束最多再等 2 秒。也可用已有 `timeout --signal=INT -k 2 60s` 作为外层限制。没有后台常驻或定时任务。每次运行独立，重复观察需手动再次运行。期间暂停主动公网自检，避免把自己的验证流量混入观察。

输出仅一条 JSON：

- `status=completed` 才表示本次捕获正常完成；失败不是“零入站”。
- `new_tcp_80` / `new_tcp_443` 为观察到 SYN 的去重连接数。捕获使用 `any` 的 Linux cooked 方向字段，排除服务器主动访问其他公网 443 服务的出站请求，同时观察本机服务发出的 TLS alert。容器、桥接可能产生重复，按地址/端口在内存合并；NAT 前后地址变化仍可能形成两个条目，数量不能直接等同物理设备数。
- `flows[].peer` 是每次运行随机密钥生成的临时 HMAC 标识，同次可关联异源流量；不显示原始 IP，跨次不能关联。此标识不能证明该连接就是安全带。
- `client_hello.sni` 仅可能为 `expected`（`lingzhiaide.com`）、`other`、`absent`。解析损坏时只给 `parse_status=malformed`。不会输出其他域名。
- `offered_versions` 是 supported_versions 扩展列出的版本；老客户端可能没有此扩展。`legacy_version` 是 ClientHello 的兼容字段，TLS 1.3 客户端也常填 TLS 1.2，不能只据这个字段判定上限。
- `cipher_ids` 是 ClientHello 提供的 cipher 编号，最多 64 项，另有完整数量及截断标志。未解析签名算法、曲线或完整握手，所以不能仅凭这个列表断言 TLS 一定成功。
- `plaintext_alerts` 只记录未加密的两字节 TLS alert，含方向、级别和数字原因码。常见原因码 40 为 handshake_failure，70 为 protocol_version，112 为 unrecognized_name；其他原因应按协议查证。加密 alert 无法从本工具解释。

最多处理 100000 包、128 个连接，每方向的暂存 TLS 数据不超过 32 KiB，原始数据只在进程内存中存在。支持以太网、Linux cooked v1/v2、IPv4、部分 IPv6 扩展头，以及按序 TCP 分段和重传重叠。它不做 IP 分片或乱序 TCP 重排，过长/截断报文也可能无法解析；`incomplete_or_gap` 或达到预算时不应把缺少 ClientHello 当作没有 TLS。

本工具看不到到达服务器之前的 DNS、SIM、4G、路由或厂家配置问题。新 TCP 为零只说明这个观察窗口没有捕获相应入站 SYN。出现目标 SNI 仍需要和实物操作时间对应，不能用公共服务上的随机访问代替设备接入证据。

离线测试使用完全合成的内存报文，不创建监听、网络连接或抓包进程：

```sh
python3 -B -m unittest -v test_passive_tls_probe.py
```
