# 单节点首次启动

本地提交：`7013eda`，未推送，仅提交 `deploy/cluster/ops.py` 和 `deploy/cluster/test/test_ops.py`。

- 从 backend 根执行 `bash deploy/cluster/clusterctl.sh up --node a`。先等待 app-a 就绪，再启动 helmet-a、belt-a、wear-api、fuda-api、backend-router 和 ingress。两个 Compose 阶段均用 `--no-deps` 和显式服务列表；已停的 B 保持停止。如果已有 B 运行，不改变 B 的状态，仍核验其运行网关。选择 B 时行为对称。A 验收通过后用原 `up` 完整启动并验两组节点。
- 保留完整配置、代际维护窗口、宿主机预检。启动后仅允许对端网关停止；运行的对端网关、所选节点网关和共享入口继续执行标签与适用挂载哈希核验。停机容器的历史代际证据仍受原维护窗保护。restart / stop 未改。
- 新目标迁移离线证据需要容器时，可在通过完整配置与预检、同一项目两应用均未运行的前提下，用已校验 manifest generation 作为环境变量，执行相同项目参数的 `docker compose … create --no-deps app-a app-b`。该步骤只创建停止态应用容器；随后核查两容器状态。没有增加 ops 子命令。

L2 本地验证：新命令级测试在旧代码上确认 A、B 各因缺少对端网关而失败；改动后 11 项无 Docker 的单元测试通过。覆盖 A/B 精确启动范围、默认全量、目标/共享服务缺失、停止对端的旧代际和运行对端的旧挂载、原 restart 行为。目标文件 `git diff --check` 通过。依赖 Compose 渲染的既有测试与真实 Docker、DM8、麒麟/NFS、容量和部署验收均未在本轮运行。
