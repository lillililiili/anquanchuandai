# 固定达梦开发发行物

官方包不提交到 Git，也不随应用交付重新分发。由部署人员从[达梦官网](https://eco.dameng.com/download/)取得与授权相符的发行物。

当前开发验证固定 `dm8_20260817_x86_Ubuntu22_64.zip`，ZIP SHA256 为 `18103060e2223ea5054a8f82fea14f5289fa3ce994a1bb4b6461b175bc687bca`。解压 ZIP，再从 ISO 提取 `DMInstall.bin`。安装器 SHA256 为 `71d0eef76796360bbc9a5ddad39c697f3fd63706f83af02c043e9b7167117c49`，镜像构建会复核。

将安装器放入忽略目录 `deploy/cluster/vendor/dm8`，复制本目录 `auto_install.xml` 到同一目录。从后端根目录执行：

```sh
docker build -f deploy/cluster/dm8/Dockerfile -t wearable-dm8:20260817 deploy/cluster/vendor/dm8
docker image inspect wearable-dm8:20260817 --format '{{.Id}} {{.RepoDigests}}'
```

此 Dockerfile 固定基础镜像、系统依赖和安装器；本机早期验证镜像的构建标签与摘要见仓库验收记录。新构建必须重新记录实际镜像摘要，不能沿用另一份构建的摘要。

镜像只安装软件，启动时不会自动创建数据库或修改 schema。DBA 在独立数据卷完成初始化：UTF-8（CHARSET=1）、大小写不敏感（CASE_SENSITIVE=0）、PAGE_SIZE=32；随后配置 COMPATIBLE_MODE=4、MY_STRICT_TABLES=7、ORDER_BY_NULLS_FLAG=2 并重启。密码从权限受限的环境文件或密钥服务传入，不写进示例命令、日志或镜像。

应用账号与 DBA 账号分离。应用运行时参数检查需要 `GRANT SELECT ON SYS.V$DM_INI TO <应用账号>`，用只读参数视图核对严格模式；不能给应用 SYSDBA 权限来绕过预检。

启动前必须执行业务 schema 迁移，再以 validate 模式启动应用。长数据、非法数字写入/转换、除零的实际失败探针必须通过，不能仅看参数存在。完整服务端版本用 `SELECT * FROM V$VERSION` 记录。

发行物随包 JDBC 为 8.1.5.60；应用当前固定并实际验证的 Maven Central 驱动为 8.1.4.93，两者分别记录。生产授权、目标麒麟主机、客户指定 JDK/容器运行时和真实设备仍需现场验证。本开发镜像内部是 Ubuntu 22 用户空间，不代表镜像内部操作系统已国产化。
