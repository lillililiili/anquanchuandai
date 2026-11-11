# 客户端云端入口

公网入口：`https://lingzhiaide.com/wear-api`。

网关默认只开放移动端接口。云端需要支持 PC 时，以
`node /runtime/wear-api-gateway/gateway.mjs --pc-clients` 启动；Caddy 的
`@wear_business` 同时匹配 `/wear-api/api/guardian/v1/*` 和 `/wear-api/api/admin/v1/*`。
网关仍绑定 `127.0.0.1:18088`，后端端口保持私有。

PC 接口采用方法和路径白名单，除登录外必须提供 `X-Wearable-Token`。
会话、账号权限和场站范围始终由后端校验，登录限流在各客户端之间共享。
整份快照写入、整份台账写入、维护接口和旧接口不开放。

本地 PC 前后台 `npm run dev` 默认连接云端；`npm run dev:local` 连接
`http://127.0.0.1:18084`，也可通过 `WEAR_BACKEND_URL` 显式指定地址。
切换环境后需要重新登录，连接云端后的业务操作会写入云端正式数据。
这些 Vite 设置只控制本地开发服务器，正式静态站点需要配置服务器代理。

安卓 `bin/run-ldplayer.ps1` 默认连接云端；本地调试显式传入
`-BackendUrl http://127.0.0.1:18084`。修改地址需要重新编译安装，attach 不会改变地址。

网关回归测试：`node --test test/*.test.mjs`。
