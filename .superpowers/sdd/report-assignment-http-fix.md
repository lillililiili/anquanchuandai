# Assignment HTTP / Jackson 修正

## 结论与边界

真实完整应用 DM8 验收证据 `output/dm8-cluster/private/acceptance-valid-1104/issue-0.json` 返回 code500，日志定位 AdminAssignmentService.executeMutation 原69行。Jackson 将 @RequestBody JSONObject 中的 items 解析为 ArrayList<LinkedHashMap>，不能直接强转 JSONObject。同入口幂等重放原82行也有相同问题。

本次仅修改该service及新增HTTP回归；没有改变Bootstrap、schema、事务/锁顺序、权限规则、版本检查或幂等指纹规则。没有操作完整应用容器/数据库。本轮验证是MockMvc真实Jackson转换+真实controller/service/query，ledger persistence与policy config使用mock；不是新的DM8/跨JVM证明。父任务负责最终fatjar真实API复测。

## TDD 与命令

工作目录 `后端代码/melhat_server-dev`；JAVA_HOME=`D:/DevTools/jdk-17.0.20.1+1`，Maven=`D:/DevTools/apache-maven-3.9.16/bin/mvn.cmd`，测试MAVEN_OPTS=`-Xmx384m`。

```powershell
mvn.cmd -B -pl ruoyi-admin -am -Dtest=AdminAssignmentHttpTest -Dsurefire.failIfNoSpecifiedTests=false '-DargLine=-Xmx512m -Djdk.net.unixdomain.tmpdir=D:/DevTools/dm8-tmp -Djava.io.tmpdir=D:/DevTools/dm8-tmp' test
```

- `output/dm8-cluster/assignment-http-red.log`：初次testCompile失败，现有JUnit不含assertInstanceOf；仅将测试断言改为assertTrue(instanceof)。不计业务RED。
- `assignment-http-red2.log`：5 tests / 5 errors，全部真实LinkedHashMap→JSONObject ClassCastException；simulationVisible=true专用重放测试命中原82行，其余命中原69行。实现修正前已读回根因栈。
- GREEN 命令沿用上方参数，`-Dtest=AdminAssignmentHttpTest,AdminPersonHistoryTest,DirectBeltRegistrationTest,DirectHelmetRegistrationTest,AdminDeviceModelTest,RemovedAssetFeaturesTest`。
- `assignment-http-green.log`：BUILD SUCCESS，34 tests / 0 failures / 0 errors / 0 skips（5+5+6+10+6+2），2026-11-04T01:36:44-05:00。
- 新增HTTP用例每次进入service均断言items是ArrayList、首项是LinkedHashMap；真实POST `/api/admin/v1/execute`。覆盖领用→重放相同结果/无重复写→归还→重放；策略开启时独立命中重放；设备scope变化拒绝；person/device旧version冲突；已提交操作撤权重放拒绝；operation内容变化409；隐藏模拟设备仍409。
- 在本入口边界检查 `AdminAssignmentService` 全部直接JSONObject casts（仅两处，均移除）；既有apply和RemovedAssetFeatures的items读取已使用getJSONObject(index)，无需改动。未扩展到无关controller state遍历或全应用审计。

## 构建

```powershell
$env:MAVEN_OPTS='-Xmx512m -Djdk.net.unixdomain.tmpdir=D:/DevTools/dm8-tmp -Djava.io.tmpdir=D:/DevTools/dm8-tmp'
mvn.cmd -B -pl ruoyi-admin -am -DskipTests package
```

`output/dm8-cluster/assignment-http-package.log` BUILD SUCCESS，2026-11-04T01:37:29-05:00。包含已提交Bootstrap 0b838e6及本修正。固定副本：`output/dm8-cluster/fdc-admin-final-ccafb8f0.jar`；SHA256 `CCAFB8F0F639968246C1A5BADABA8AAF14E215E5274D816B9AA1FE3B244493E7`。来源 `后端代码/melhat_server-dev/ruoyi-admin/target/fdc-admin.jar`，副本hash读回一致。没有运行无关fullsuite或Docker构建。

## 代码变更说明

|文件/类|方法|方法作用|本次修改作用|
|---|---|---|---|
|AdminAssignmentService|executeMutation|业务策略、幂等及当前权限检查|两处请求items遍历改getJSONObject(index)，兼容Jackson Map，校验顺序/结果保持|
|AdminAssignmentHttpTest|setup/send/issue及5条测试|构造真实HTTP消息转换与可检查的台账写入|复现首次/重放异常并证明权限、版本、幂等及策略约束保持|
