# 工具链与构建（S0-02）

记录日期：2026-09-08。以本机实测为准，编译目标仍按仓库 POM。

## 版本锁定

| 工具 | 仓库声明 | 本机实测 | 说明 |
| --- | --- | --- | --- |
| JDK 编译目标 | POM `java.version=1.8`，compiler `source/target=8` | 运行 JDK：**Temurin 17.0.20.1** | 用 JDK 17 跑 Maven 编译 Java 8 字节码。不要改成 JDK 17 language level。 |
| Maven | 未锁 wrapper | **3.6.3**（`E:\Tools\Maven\apache-maven-3.6.3`） | |
| Spring Boot | 父 POM **2.5.14** | 同仓库 | |
| `spring-boot-maven-plugin` | admin 模块 **2.1.1.RELEASE** | 与 Boot 2.5.14 不一致 | S0 不改插件版本，只记录。若日后 repackage 异常再升级到与 Boot 对齐的 2.5.x。 |
| Node | 未锁 engines | **v22.19.0** | |
| 包管理 | `package.json` 写了 `packageManager: bun@1` | 实际用 **npm 10.9.3** | PC **不要用 bun 安装**。以 `package-lock.json` + npm 为准。 |
| 后端端口 | `application-*.yml` `18084` | 18084 | |
| PC 开发代理 | Vite `/dev-api` → 后端 | 默认 5173；本机曾用 5175 | 以 `.env.development` 的 `VITE_APP_BASE_API=/dev-api` 为准。 |

## 构建命令

后端（在 `后端代码/melhat_server-dev`）：

```text
mvn -pl ruoyi-admin -am package -DskipTests
```

带测试（admin 已锁定 `maven-surefire-plugin` 2.22.2 以执行 JUnit 5；父工程默认 2.12.4 会跑出 0 tests）：

```text
mvn -pl ruoyi-admin -am test
```

产物：`ruoyi-admin/target/fdc-admin.jar`。

PC（在 `pc前端代码/melhat_pc-main`）：

```text
npm install
npm run dev
npm test
npm run build:prod
```

## 本机覆盖配置（不要提交）

Spring Boot 从工作目录加载 `ruoyi-admin/config/application-dev.yml`（已 gitignore）。  
启动后端时工作目录应为 `ruoyi-admin`，否则不会读到该文件。

仓库内 `src/main/resources/application-dev.yml` 指向共享/历史库主机，密码走环境变量 `${DB_PASSWORD:}`，**不要把本机 3307 / 明文密码写进该文件**。

## 本地 JAR

| 文件 | 引用 | 来源 |
| --- | --- | --- |
| `ruoyi-admin/lib/jna.jar` | admin POM `system` 依赖 `com.sun.jna:jna:7.0.0` | 仓库内二进制，厂商/上游来源未在文档中证明 |
| `ruoyi-admin/lib/examples.jar` | `com.sun.jna.examples:examples:7.0.0` | 同上 |

打包可重复性依赖这两份 JAR 仍在 `lib/`。S0 未做哈希核验与许可证归档，S11 前补。

## 历史台账源码（S0-01）

计划中的 `sql/wearables`、`deployment/wearables` **当前仓库未找到**，记为未找回。找回后只在隔离环境评估，不覆盖本工程。
