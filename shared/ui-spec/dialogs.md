# 前后台统一弹窗

2026-10-16。沿用现有 Sketch 字体、图标、颜色和浮层 token；本次统一弹窗几何与表单布局，不修改业务接口。

后台后续视觉修正见 [后台弹窗原稿映射](admin/dialogs.md)：后台专用样式覆盖此处的通用外观，使用原画板 20px/16px 圆角与 35px 表单控件；操作按钮直接复用页面外的 32px Sketch 按钮组件，底部操作区透明无外框。下面的尺寸与业务结构仍保持兼容；前台不启用该覆盖。

## 尺寸与结构

| size | 宽度 | 用途 |
| --- | --- | --- |
| confirm | 440px | 删除、放弃修改等确认 |
| compact | 650px | 邀请成员、重置密码等短表单 |
| regular（默认） | 880px | 普通表单、只读详情 |
| wide | 1000px | 地图、权限、发放回收、宽表 |

视口边缘留白至少 24px，最大高度为 `100dvh - 48px`。标题栏和操作栏不参与内容滚动。标题字号/行高 18/26px，表单 14/22px；继续使用公共普通控件的 32px 规格。字段间距 16px、列间距 20px、标签间距 8px。

两端入口最后导入 `@ui-spec/dialog.css`。规则仅匹配 `.ui-dialog`，不影响页面内表单、固定分栏及登录页。

## 后台用法

`ModalPanel` 保留原生 `<dialog>`、`open`、`title`、`headingId`、`close` 事件；不再提供右侧抽屉模式。关闭事件由业务组件处理，不能绕过 dirty/busy/版本检查。

```vue
<ModalPanel :open="open" size="regular" layout="form" title="编辑资料" @close="close">
  <form ref="formRef" class="dialog-form" @submit.prevent="save">
    <div class="dialog-form-body">
      <div class="form-grid">
        <label>名称<input v-model="name" /></label>
        <label>编号<input v-model="code" /></label>
        <label class="wide">备注<textarea v-model="note" /></label>
      </div>
      <!-- 字段错误紧邻字段，提交错误放在滚动内容末尾 -->
    </div>
    <div class="dialog-form-footer">
      <span>版本信息</span>
      <button type="button" @click="close">取消</button>
      <button type="submit">保存</button>
    </div>
  </form>
</ModalPanel>
```

普通内容弹窗使用默认 `layout="content"`；外置操作使用 `#footer`。不要把提交按钮移出原有 form，不要嵌套 form。数据尚未存在时 footer 也须使用条件渲染，避免关闭状态访问空记录。

## 前台用法

继续使用 `openModal({ title, view, props, footer, size, layout })` 和 `AppModal`。已有 `wide: true` 兼容映射到 1000px；显式 `size` 优先。表单弹窗传入 `layout: 'form'`，表单内部使用上面的 body/footer 结构，字段网格可用 `dialog-grid`。

内容容器达到 640px 后普通字段排两列；否则单列。备注、地图、成员选择、权限配置用 `.wide` 跨整行。页面内侧栏和独立详情页不使用这个布局模式。

## 已迁移入口

| 端 | 入口 | 尺寸/形式 |
| --- | --- | --- |
| 后台 | 装备新建、编辑 | regular / form |
| 后台 | 领用、归还 | wide / form |
| 后台 | 人员、组织、厂站维护 | regular / form |
| 后台 | 区域地图、班次、账号、角色维护 | wide / form |
| 后台 | 账号密码重置 | compact / form |
| 后台 | 授权效果预览 | wide / content + footer |
| 后台 | 基础资料只读详情、操作日志详情 | regular / content |
| 后台 | 工作台只读明细 | wide / content |
| 后台 | 操作影响、放弃修改确认 | confirm / content + footer |
| 前台 | 调度分组新增/编辑、围栏成员选择 | regular / form |
| 前台 | 邀请成员 | compact / form |
| 前台 | 围栏进出记录及模拟位置表单 | wide / form |
| 前台 | 删除等通用确认、SOS 结束确认 | confirm / content + footer |
| 前台 | 既有记录、详情、历史表格弹窗 | regular 或兼容 wide / content |

## 交互与验收入口

- 内部日期/选择浮层使用原 `usePopup` 层级和 Escape 处理。前台父弹窗只响应未被消费的 Escape。
- 前台记录列表切换到详情时保留最初页面触发按钮，关闭后返回该按钮；已移除或禁用的触发按钮不会强行获取焦点。
- 后台继续走现有未保存确认、提交中禁止关闭、授权预览和版本校验。
- 开发组件页：前台 `/portal-spec.html`、后台 `/admin-spec.html`，均新增四种尺寸、长表单、日期、多选示例。
- 前台隔离业务验收：在前台目录运行 `node node_modules/vite/bin/vite.js --config review.vite.config.js`，访问 `http://127.0.0.1:5193/tests/fixtures/modal.html`。仅开发环境、内存数据、API 请求阻断；此配置禁止生产构建。
- 后台隔离业务验收沿用 `review.vite.config.js`，端口 5183。
- 验收截图和结果：`output/modal-unification/index.html`。自动化交互合同测试在后台 `modal.test.js`；包括被内部浮层消费的 Escape、失效焦点、弹窗替换后的焦点恢复和尺寸兼容。
