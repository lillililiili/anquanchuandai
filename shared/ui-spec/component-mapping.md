# 组件与 Sketch 图层对照

生产采用的参数以具体组件示例优先；全部可见原始测量另见 `evidence/`。业务容器尺寸沿用现有页面布局。

|组件|状态|实现|采用规格|原稿图层 ID|
|---|---|---|---|---|
|主按钮|默认/悬停/按下/禁用|.btn.primary / .button.primary|32px / 14px / 22px；四态独立颜色|4HFYwkQ-FC6Gp4FBgQYsn / xXg75oJxJl_WGdmtTTFuN / wFGy3DfrBzcg5MhEENjKM / A2OOwHqxrDM9sRhfmcp8W|
|按钮规格|紧凑/常规/大|按钮 small / 默认 / 登录主操作|24/32/40px；紧凑文字12px，常规及大按钮14px|CkstYJO3Hiokoedmyf64Z / 4HFYwkQ-FC6Gp4FBgQYsn / t4_AdXg-GSXV4b5IZwBEI|
|输入框|默认|AppInput / 原生 input / UiDatePicker|32px高，4px圆角；透明底；边框#83F6FD alpha .35|WH_CO_Ryr9t91AmzsRExp|
|下拉选项|默认/悬停/选中|UiSelect|28px行；6px容器内边距；2px行距；4px圆角|vtlVFKvKZ4Sh3tlRTk-cz / I0Y7nDcT1zSenZWCzO4cL / VThA-ge8SrGF2fZV7JafD|
|日期面板|展开|UiDatePicker|312px日历；日期时间504px；单元32px高；16px内边距|YkUSGQ69TR712LBDSGBvs|
|文字提示|展开|tooltip.js|.9黑色；4px圆角；4px 8px内边距；14/22px|D1Y8tE-ndrB_DsfKhfE7C|
|复选框|选中/未选中|input[type=checkbox]|16px正方形；1px边框；原稿勾选矢量|Zb7zYWwChCrTirxpNeCbu / 7u3yvNPyer5rrFwTvhwHX|
|单选框|未选中/选中|input[type=radio]|16px圆形；8px内圆|VgJEMc5_0dxx6uZbIw0AP / Ult4uE8ZaeAL4tmb-ZpLm|
|开关|关/开/禁用|UiSwitch|32×20px；16px滑块；2px边距|g__GhdR1d9dK-EQIOHb7m / i8ZDtnIG6HRxJI076cCjY / 3k6gBRbiF_I2Ti3k5B7Nc|
|标签|常规/紧凑|tag / badge|26/22px，3px圆角；红色组件底透明度.38优先于色板.25|u5l8kj4z_2rvYWPo3EMKx / LOi51u2qJoWht0skIr8BL|
|页签|选中/默认|AppTabs / workspace-tabs|分别保留面板页签和下划线页签规格|UXsXflFbJ-yR1M6B338yu / BUcZpmTAf5eb9NRwjPINo / Ttmhf3aXtHv0A79QXBwan|
|分页|常规|pagination / UiSelect|32px高；选择器4px圆角；沿用现有翻页行为|d8SUk0URGgv8LkX31aPFB / Hstb7oae8Z0KvRQFj_wp2|
|树|默认/选中|tree-branch / 原生权限复选框|保留树层级，复选框16px，选中使用规范强调色|7u3yvNPyer5rrFwTvhwHX / VBXfZnPfUAK0sWGJfSe0s|
|表格|表头/内容分隔线|admin-table / table-scroll|规范色板表头/奇偶行/选中态；固定列叠加背景防透出|voEls8l2RIhT3k4tQk1V6 / 1vXkt5jIielgtR4ipvzy8|
|卡片|业务画板补充|panel / card|rgba(80,177,249,.12)，12px圆角；不作为控件通用圆角|gikbC3t8uxeoq7IyvXlGB / 1Q6Q1uJi3mAamRMsUqtGu|

数据接口：`modelValue` / `update:modelValue` / `change`；选择器同时兼容现有原生 change 事件。日期字符串保持本地 `YYYY-MM-DD` / `YYYY-MM-DDTHH:mm[:ss]`，不调用 UTC 转换。

状态核对：颜色及 alpha、背景、边框、圆角、字重、字号、行高、尺寸见 JSON；图层继承可见性由抽取器过滤。说明文字只作为来源上下文，不作为产品文案或样式值。
