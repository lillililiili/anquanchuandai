# Agent 功能流程测试文案

## 一、登录与退出流程

### 测试用例 1：基本登录流程
**输入**：`帮我登录`
**预期**：Agent 应跳转到登录页面，用户手动完成登录

### 测试用例 2：退出登录流程
**输入**：`退出登录`
**预期**：Agent 调用 `logout` 工具，退出当前登录状态

---

## 二、轨迹回放功能

### 测试用例 3：查看轨迹回放
**输入**：`我想看轨迹回放`
**预期**：Agent 跳转到轨迹回放页面

### 测试用例 4：选择人员查询轨迹
**输入**：`查看张三的轨迹`
**预期**：
1. Agent 调用 `selectPerson` 工具选择人员"张三"
2. 提示用户选择日期范围
3. 调用 `executeQuery` 执行查询

### 测试用例 5：指定日期范围查询
**输入**：`查看李四上周的轨迹`
**预期**：
1. Agent 调用 `selectPerson` 选择"李四"
2. 调用 `selectDateRange` 设置日期范围（上周）
3. 调用 `executeQuery` 执行查询

---

## 三、电子围栏功能

### 测试用例 6：查看围栏列表
**输入**：`查看电子围栏列表`
**预期**：Agent 调用 `queryFenceList` 工具获取围栏列表

### 测试用例 7：筛选围栏
**输入**：`查询类型为施工区域的围栏`
**预期**：Agent 调用 `queryFenceList` 并传入 `fenceType` 参数

### 测试用例 8：添加围栏
**输入**：`添加一个新围栏`
**预期**：Agent 调用 `addFence` 工具，跳转到围栏编辑页面

### 测试用例 9：编辑围栏
**输入**：`编辑围栏A`
**预期**：
1. Agent 调用 `queryFenceList` 获取围栏列表
2. 调用 `editFence` 工具并传入围栏ID

### 测试用例 10：删除围栏
**输入**：`删除围栏B`
**预期**：Agent 调用 `deleteFence` 工具并传入围栏ID

### 测试用例 11：设置围栏信息
**输入**：`把围栏名称改为"测试区域"`
**预期**：Agent 调用 `setFenceName` 工具设置围栏名称

---

## 四、告警记录功能

### 测试用例 12：查看告警记录
**输入**：`查看告警记录`
**预期**：Agent 调用 `queryAlarmRecord` 工具获取告警记录列表

### 测试用例 13：分页查看告警
**输入**：`查看第2页的告警记录`
**预期**：Agent 调用 `queryAlarmRecord` 并传入 `pageNum: 2`

### 测试用例 14：查看告警详情
**输入**：`查看告警12345的详情`
**预期**：Agent 跳转到告警详情页面，传入 `alarmId: 12345`

---

## 五、对讲功能

### 测试用例 15：发起单呼
**输入**：`给张三打电话`
**预期**：
1. Agent 调用 `selectCallTarget` 选择对讲对象（单呼，personName: 张三）
2. 调用 `startIntercomCall` 发起呼叫

### 测试用例 16：发起组呼
**输入**：`呼叫安全一组`
**预期**：
1. Agent 调用 `selectCallTarget` 选择对讲对象（组呼，groupName: 安全一组）
2. 调用 `startIntercomCall` 发起呼叫

### 测试用例 17：发起群呼
**输入**：`呼叫张三和李四`
**预期**：
1. Agent 调用 `selectCallTarget` 选择对讲对象（群呼，teamNames: [张三, 李四]）
2. 调用 `startIntercomCall` 发起呼叫

### 测试用例 18：查看对讲记录
**输入**：`查看对讲记录`
**预期**：Agent 调用 `queryIntercomRecords` 工具获取对讲记录列表

### 测试用例 19：筛选对讲记录
**输入**：`查看单呼的对讲记录`
**预期**：Agent 调用 `queryIntercomRecords` 并传入 `intercomType: "01"`

### 测试用例 20：删除对讲记录
**输入**：`删除对讲记录123`
**预期**：Agent 调用 `deleteIntercomRecord` 工具并传入 `id: 123`

---

## 六、TTS播报功能

### 测试用例 21：发送单播报
**输入**：`给张三发播报"请到安全区域集合"`
**预期**：
1. Agent 调用 `selectBroadcastTarget` 选择播报对象（单播，personName: 张三）
2. 调用 `setBroadcastText` 设置播报内容
3. 调用 `sendBroadcast` 发送播报

### 测试用例 22：发送组播报
**输入**：`给安全一组发播报"注意安全"`
**预期**：
1. Agent 调用 `selectBroadcastTarget` 选择播报对象（组播，groupName: 安全一组）
2. 调用 `setBroadcastText` 设置播报内容
3. 调用 `sendBroadcast` 发送播报

### 测试用例 23：发送群播报
**输入**：`群播张三和李四"开会了"`
**预期**：
1. Agent 调用 `selectBroadcastTarget` 选择播报对象（群播，teamNames: [张三, 李四]）
2. 调用 `setBroadcastText` 设置播报内容
3. 调用 `sendBroadcast` 发送播报

### 测试用例 24：查看播报记录
**输入**：`查看播报记录`
**预期**：Agent 调用 `queryBroadcastRecords` 工具获取播报记录列表

### 测试用例 25：筛选播报记录
**输入**：`查看单播的播报记录`
**预期**：Agent 调用 `queryBroadcastRecords` 并传入 `broadcastType: "01"`

---

## 七、监控功能

### 测试用例 26：查看监控设备列表
**输入**：`有哪些监控设备`
**预期**：Agent 调用 `queryMonitorDevices` 工具获取设备列表

### 测试用例 27：切换监控设备
**输入**：`查看1001号设备的监控`
**预期**：Agent 调用 `selectMonitorDevice` 工具并传入 `hatNumber: 1001`

### 测试用例 28：按人员查看监控
**输入**：`查看张三的监控`
**预期**：Agent 调用 `selectMonitorDevice` 工具并传入 `bindUserName: 张三`

### 测试用例 29：进入监控详情
**输入**：`查看监控详情`
**预期**：Agent 调用 `enterMonitorDetail` 工具进入详情页面

---

## 八、组合流程测试

### 测试用例 30：完整围栏管理流程
**输入**：`帮我新建一个叫"危险区域"的围栏`
**预期**：
1. Agent 调用 `addFence` 添加围栏
2. 调用 `setFenceName` 设置围栏名称为"危险区域"

### 测试用例 31：查看某人轨迹并播报
**输入**：`查看张三今天的轨迹，然后通知他注意安全`
**预期**：
1. Agent 调用 `selectPerson` 选择"张三"
2. 调用 `selectDateRange` 设置今天日期
3. 调用 `executeQuery` 执行查询
4. 调用 `selectBroadcastTarget` 选择播报对象（单播，personName: 张三）
5. 调用 `setBroadcastText` 设置播报内容
6. 调用 `sendBroadcast` 发送播报

### 测试用例 32：查看告警并联系当事人
**输入**：`查看最新告警，然后给张三打个电话`
**预期**：
1. Agent 调用 `queryAlarmRecord` 获取告警记录
2. 调用 `selectCallTarget` 选择对讲对象（单呼，personName: 张三）
3. 调用 `startIntercomCall` 发起呼叫

---

## 九、边界情况测试

### 测试用例 33：模糊意图
**输入**：`我想看看围栏`
**预期**：Agent 应能识别意图并调用 `queryFenceList` 查询围栏列表

### 测试用例 34：多意图混合
**输入**：`查看告警记录和对讲记录`
**预期**：Agent 应能分别调用 `queryAlarmRecord` 和 `queryIntercomRecords`

### 测试用例 35：无参数请求
**输入**：`帮我查一下`
**预期**：Agent 应询问用户具体想查询什么

### 测试用例 36：连续操作
**输入**：`先查看围栏，然后添加一个新围栏`
**预期**：
1. Agent 调用 `queryFenceList` 查询围栏列表
2. 调用 `addFence` 添加新围栏

---

## 测试建议

1. **按模块测试**：建议按功能模块逐一测试，确保每个工具调用正确
2. **参数传递**：重点检查参数是否正确传递（如人员姓名、日期格式等）
3. **跳转验证**：验证页面跳转是否正确，参数是否正确携带
4. **错误处理**：测试边界情况，如参数缺失、参数错误时的处理
5. **连续操作**：测试多步骤流程的连贯性
