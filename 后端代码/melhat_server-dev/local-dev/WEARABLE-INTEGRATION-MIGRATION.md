# 部署适配配置登记

执行 `python local-dev/migrate-wearable-integrations.py <build/wearable-release-目录>`。

工具读取当前 `melhat-backend` 的实际部署参数，只把已配置地址及密钥的安全帽媒体适配登记到 `external_integration`。稳定 ID 为 `adapter-helmet-media-site-1`，与后续真实媒体响应调用 `ExternalDataStore.record("helmet-media", ...)` 一致。名称、类型、无凭据的控制地址、密钥环境变量引用、启用状态和 `managed=true` 来自部署配置；不调用远程接口，也不下发设备操作。

首次登记使用 `NOT_CONNECTED`、空 `lastSyncAt`，表示尚无此表中的真实外部数据同步依据。已有记录只补齐部署配置，保留真实同步状态、时间和数据；重复执行无变化。并发更新使用原完整 body 的比较条件，不能覆盖刚产生的真实回执。不会写入 `external_data_record`。

厂家只有默认服务器地址、没有已配置账号时，不创建一条假厂家接入。需要实际厂家账号和接入授权之后再按真实配置登记。

执行前的表内容和执行结果保存在发布目录 `external-config-migration/`；目录由 Git 忽略。环境变量和密钥明文不会写入业务表或控制台。此次实际登记的媒体来源启用，外部数据记录数为零，厂商账号未配置。
