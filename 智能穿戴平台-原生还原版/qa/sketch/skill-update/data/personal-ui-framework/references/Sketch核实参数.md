# Sketch 核实参数

核实日期：2026-10-10。源文件：`D:/wx_chat/xwechat_files/wxid_x9ztlatrmfbm22_4b89/msg/file/2026-10/UI规范.sketch`。本次解析原生 JSON 共52,178个图层、8个业务画板，配合Sketch内置预览核对语境。这里记录的是本稿证据，不替其他设计源背书。

源文件SHA-256：`20EE13BFF161045011C20CB5C4FDA6D8128A6E74C97D8DEC7C61F378D137C36F`。

目录：1证据边界；2完整颜色表；3字体；4控件；5交互；6组件索引；7画板实例；8项目映射；9历史撤回。

## 1. 如何使用这些证据

- **规范规则**：规范区明确文本、颜色行与组件状态对照，可用于同类组件。
- **组件样例**：实际图层给定的尺寸和外观。属于该组件/状态/大小变体，不能变成所有组件的统一尺寸。
- **画板实例**：某业务画板的局部风格、字体或透明度，不自动替代规范区。
- **项目映射**：为了满足现有产品布局、交互、展示尺寸或兼容性而作的实现选择；在项目验收中注明，不作为Sketch原始值。

所有图层 ID、完整路径、局部 Frame、启用的填充/边框、文字属性见 [Sketch证据.json](Sketch证据.json)。Frame 是相对父图层坐标。判断可见稿要检查祖先可见性；隐藏的旧版图层不能用作当前可见画板的依据。颜色统计包括提取到的填充、边框、渐变节点和文字 run，不包括位图内部像素。

## 2. 颜色规范：完整53行

以下 RGB 与 alpha 必须一起记录。alpha 是颜色本身透明度；实际组件还可能叠加样式或图层 opacity，并受底色影响。不能把色块在屏幕上的取色结果当作原始值。

色表标题实际写 `Color Tokens_Light Mode 色彩规则`（`m8-yk1_KsogWnGbiD_tdD`），但表中是白字、深蓝页面底，且本稿长页原生背景也是深色。仅凭标题不能推出完整Light主题；以下不擅自改成Light/Dark两套映射。

| 色表用途 | RGB | alpha | 色块图层 ID |
| --- | --- | --- | --- |
| 主色一default | `#83F6FD` | 1 | `-wxo7UjqvqneQNTivHtc5` |
| 主色一hover | `#A0F8FD` | 1 | `n7CkTUcdpqHP7UXB2RmbJ` |
| 主色一active | `#5DCAD2` | 1 | `UYUa-g11WkOm_jP1rEsGi` |
| 主色一disabled | `#C4FBFE` | 1 | `ZqNiVP01gnKu5b96oTQGJ` |
| 主色二default | `#4FAFF7` | 1 | `qRBKuAXstQZQ-Adi1786E` |
| 主色二hover | `#7FCEFA` | 1 | `RtqN3Tnmau-jJigZ5Ulgy` |
| 主色二active | `#3C89F5` | 1 | `5HRorMkldRqfvl9vuwTiP` |
| 主色二disabled | `#193A60` | 1 | `0DqUfZvbn2Pe4RWtujfBL` |
| 错误色 | `#DE554F` | 1 | `bgx6_Z0f5bZSkU5MQnMpC` |
| 错误色hover | `#E57163` | 1 | `7kIY4YA3JBjw8xrZ9Ti4i` |
| 错误色active | `#A03E35` | 1 | `iDyLw7sFKwPzxSPx-Oa-J` |
| 错误色disabled | `#F4BCB2` | 1 | `8n0Bqat4ECiHiQZJn1zpV` |
| 二级警告色 | `#F09840` | 1 | `pbsEu087YP8CGkPvrF3Fi` |
| 二级警告色hover | `#EC9A5E` | 1 | `jXBrWpcD3_ly-TCrrRuiF` |
| 二级警告色active | `#B16022` | 1 | `g0wz-sZhLBPKg0wIycB8P` |
| 二级警告色disabled | `#F4BC93` | 1 | `l_fCxcXcC0qGUklaJ2rfq` |
| 三级警告色 | `#FEF770` | 1 | `q4n21qokeoWg7KlzJmIqq` |
| 三级警告色hover | `#FEF886` | 1 | `jKEY74xfLrVExmTSWQVK-` |
| 三级警告色active | `#DAD245` | 1 | `FPRBQemcDpuTP94FN4By8` |
| 三级警告色disabled | `#FEFBAA` | 1 | `4Z0TPLR19NRHtu-yj452N` |
| 成功色 | `#71E96F` | 1 | `T5RcUyQT5IghgzpSxeiO5` |
| 成功色hover | `#73BE91` | 1 | `n5A0ADBRu3fBju5r-GP85` |
| 成功色active | `#3B865C` | 1 | `bNvGuLBHdP6CBtLMKp0SV` |
| 成功色disabled | `#A2D8B5` | 1 | `q-NWfrwzf3JJdPWedMImW` |
| 一级文字色 | `#FFFFFF` | 1 | `jtSw0dSaOLMCbpJZ8r685` |
| 二级文字色 | `#D1DAE5` | 1 | `s8CDc_MMPf_T-I4Ansvub` |
| 三级文字色 | `#B0BECB` | 1 | `caLqFh68iaBHwJ0xAuBjN` |
| 禁用文字色 | `#677987` | 1 | `iO7e00gReqiGS0Gu97Wc8` |
| 链接文字色 | `#83F6FD` | 1 | `DkqsLz4stLMaeLeapa9cq` |
| 默认页面底层背景色 | `#121E37` | 1 | `lmrmXOJDe_YhUu9GpxILn` |
| 卡片背景色 | `#50B1F9` | 0.12 | `StgLM69wj7o-zvpT2mSnq` |
| 组件背景色1 | `#83F6FD` | 0.2 | `dahG5nevYHNrnmj2rTPxa` |
| 组件背景色2 | `#83F6FD` | 0.5 | `g-wfUunFHDxHfl3kZ3Mjt` |
| 组件背景色3 | `#25556F` | 0.2 | `FFge0hZ_AL7ZJ5RU1nL_e` |
| 组件背景色4 | `#7FCEFA` | 0.15 | `-8ZXFXlMTJL4LS69yUA9i` |
| 组件背景色5 | `#3C89F5` | 0.2 | `MebGf0ilqOrAaDxYrVs6X` |
| 组件背景色6 | `#295F75` | 1 | `2oSUB8OPHFLejMvhOzGRK` |
| 分割线色 | `#FFFFFF` | 0.1 | `z-NLC-qMpg58iEm8Ytzlo` |
| 边框色 | `#83F6FD` | 0.5 | `r9ta2IVBN-3LwYIyoc78h` |
| 边框禁用色 | `#83F6FD` | 0.2 | `Y3XSweGgWbZE1V23yPY0U` |
| 下拉背景色 | `#2E6086` | 1 | `b2Z78PKjHnxv19CT7sopb` |
| 表头背景色 | `#25556F` | 1 | `kUxpaXQ5XGi1MBGFVI2Wv` |
| 表格选中色 | `#254570` | 1 | `lkX-HL0rLIAlvX88PF1Hy` |
| 斑马格深色 | `#0D1D3A` | 0.9 | `vmcXjlIatgc3wjlAqoipM` |
| 斑马格浅色 | `#112345` | 0.8 | `0V6RIoqr2m-cKz-yIjeHV` |
| 按钮默认色 | `#4FAFF7` | 1 | `_Kaa4yFm3ygT29qzrYYIw` |
| 按钮悬浮色 | `#7FCEFA` | 1 | `o15yTiYGHXHvRFsEbMD1g` |
| 按钮点击色 | `#3C89F5` | 1 | `FfPHU5d9_LMRgFUEljC5m` |
| 按钮禁用色 | `#193A60` | 1 | `JPqAYwHovoaSR1oKvMgvs` |
| 标签色-红色 | `#DE554F` | 0.25 | `FqibCYUea8NQMo3HtcgDm` |
| 标签色-橙色 | `#F09840` | 0.2 | `SpboQ5AsOOj833lyUAm50` |
| 标签色-绿色 | `#71E96F` | 0.2 | `qFWSchYWZxE5vec3pbQve` |
| 标签色-主题色 | `#4FAFF7` | 0.2 | `6AUJ747WSqISxpZIschKV` |

补充说明：

- 表格的深/浅行分别保留0.9/0.8，不改成不透明填充。
- 六档组件背景分别保留用途；其中部分条目RGB相同而alpha不同，仍是不同令牌，不能因RGB相同而合并。
- 红标签色表为0.25，标签组件常规样例为0.38。两者分别记录，按所用样例选择，不能宣称全稿统一0.16。
- 原稿确实给出所有品牌/语义四态，但没有在这些行中建立两套完整主题。不得另外推导所谓Dark禁用值。
- 主色、错误、警告和成功表达的语义沿用各颜色行；具体业务告警等级仍以目标项目数据含义为准。没有充分图层关联时，不强制全部深色P3变蓝。

## 3. 字体规范与实际画板

### 3.1 明确推荐与基础阶梯

规范表推荐：macOS中文PingFang（`8KS5lKYgB2i1jgRqkXQ9u`）；Windows中文思源黑体（`cyGRgXcTj5l0ofwuuqpd9`）；两平台英文/数字均Arial（`KlMNTbOGHFsfeA1HEp3PA`、`RzpvbSxw1p3gOXd8gX8fT`）。这些是表格单元格内容，不能把绘制单元格本身的Helvetica元数据误认成推荐。

字重原文为“默认字重：regular”“加粗字重：bold”（`tqjSh5F6VLLY4t2uZA8ye`、`Wh0kKVFAF4RRYTRSOC0lc`）。没有写“仅CSS400/600”。Bold样例通常为SourceHanSansCN-Bold；一处正文加粗样例为Medium，要保留差异。

| 用途 | 字号 / 行高 px | regular图层 ID | bold图层 ID |
| --- | --- | --- | --- |
| 标题大 | 24 / 32 | `u_pHZ-YUoNfr1q8ZsBBvx` | `h4Q_iAJbZ_47L9WZw86gP` |
| 标题中 | 18 / 26 | `QpTXHu-2-CK1sxIUZIjux` | `de_gcWw0DF1AMIvVbfwuj` |
| 标题小 | 16 / 24 | `1jWIgp6g8JYSVb25Kj4tP` | `c0SeQvmpeMfve5layGmWZ` |
| 正文 | 14 / 22 | `YwnDZRx9gfUX8P8kHjruI` | `JThgvRhqG5Wa44DCKLk_S` |
| 辅助文字 | 12 / 20 | `PtZsI-tLvf8Ca3tWb4Vpg` | `cUUCWEs4EMlZJvKIzetWd` |

辅助加粗层名称写14px但实际字体size为12，以上采用实际属性并保留该冲突。正文Medium样例ID：`ZwNrqGsO4utmG5r9UcD26`。

### 3.2 画板实例，不提升为全局阶梯

- 导航20px Medium：`F46BA73B-AD7C-46A4-90AB-6F9AD735AD0D`。
- 指标21px Bold：`0418B125-CFA7-4EFB-B666-93D953D4A5EE`。
- 系统标题30px Heavy：`7D1B84FD-6446-4834-8055-06EEE12D2CEE`。
- 数字与单位混排14/11/8px：`4A074EA6-2803-405F-B7BA-EC775A3BD209`。
- 业务文字实际还存在10px、9px等局部实例；不能宣称全稿禁止基础阶梯之外任何字号，也不能把这些小字自动用于普通表单。

本次提取未发现Roboto。网页可用思源黑体、PingFang SC及微软雅黑兜底；具体平台回退、CSS字重映射与`tabular-nums`是工程选择。指标按目标展示尺寸选择，记录例外，不机械压成24px，也不把现有大屏50px写成源稿规格。

## 4. 控件的已核实状态和大小

下面均为顶部组件规范区的实际控件外框，而非整个展示板尺寸。控件宽度通常是样例宽度，不要求所有项目固定为该宽度。

### 4.1 输入框

普通输入框样例宽300、高32、圆角4px。Default/Hover/Focus/Disable文字与同一行控件的位置已核对；普通态原始fills未启用，所以是透明背景，不是`#0E182D`或表格深行底。

| 状态 | 填充 | 边框 | 图层 ID |
| --- | --- | --- | --- |
| Default | 无启用填充 | 1px `#83F6FD` / alpha0.35 | `OO_JcofjMEpaejS9TiU6s` |
| Hover | 无启用填充 | 1px `#83F6FD` / alpha1 | `fyhpzVlnlv6Z-szUUqXTU` |
| Focus | 无启用填充 | 2px `#83F6FD` / alpha1 | `ii-3dhDcMuCP6O9_aM8eh` |
| Disable | `#7FCEFA` / alpha0.2 | 1px `#83F6FD` / alpha0.2 | `NWroIm5TfgG_SZoHqW39N` |

聚焦加粗边框的CSS实现应防止控件外尺寸变化；外框阴影或内描边可作为工程映射，但不能声称原稿有未出现的模糊光晕。

### 4.2 按钮与下拉

| 样例 | 外框 / 圆角 | 填充 | 图层 ID |
| --- | --- | --- | --- |
| 主按钮Default | 60×32 / 4px | `#4FAFF7` | `4HFYwkQ-FC6Gp4FBgQYsn` |
| 主按钮Hover | 60×32 / 4px | `#7FCEFA` | `xXg75oJxJl_WGdmtTTFuN` |
| 主按钮Active | 60×32 / 4px | `#3C89F5` | `wFGy3DfrBzcg5MhEENjKM` |
| 主按钮Disable | 60×32 / 4px | `#193A60` | `A2OOwHqxrDM9sRhfmcp8W` |
| 小按钮 | 40×24 / 4px | `#4FAFF7` | `CkstYJO3Hiokoedmyf64Z` |
| 大按钮 | 76×40 / 4px | `#4FAFF7` | `t4_AdXg-GSXV4b5IZwBEI` |
| 下拉菜单 | 300×100 / 4px | `#2E6086` | `vtlVFKvKZ4Sh3tlRTk-cz` |
| 下拉菜单另一内容量 | 300×160 / 4px | `#2E6086` | `BNoE3V5mAf546mLJqI5bm` |

下拉内容高度由选项数量决定，不固定100或160。原生select的系统弹出菜单受浏览器/系统控制；保留原生行为时，注明能控制的样式范围，不能只为外观换掉交互。

### 4.3 复选、单选、开关和标签

| 样例 | 实际外框与颜色 | 图层 ID |
| --- | --- | --- |
| Checkbox默认/hover | 16×16，透明底，1px青`#83F6FD`边 | `32EMICkB5gc53lKl3ovqh` / `Hh-135H2P8kKAvbPcWcqC` |
| Checkbox选中 | 16×16，青色填充和边框 | `Zb7zYWwChCrTirxpNeCbu` |
| Checkbox active | 16×16，边`#5DCAD2` | `2MdottpuRVU78g4hftEFC` |
| Radio选中外环/内点 | 外16×16，1px青边；内8×8青色 | `h-t4IViD_63gZ0EWVrdh2` / `Ult4uE8ZaeAL4tmb-ZpLm` |
| Switch关闭 | 32×20，radius12，青alpha0.2 | `g__GhdR1d9dK-EQIOHb7m` |
| Switch开启 | 32×20，radius12，`#3B865C` | `i8ZDtnIG6HRxJI076cCjY` |
| Switch禁用 | 32×20，radius12，`#A2D8B5` | `3k6gBRbiF_I2Ti3k5B7Nc` |
| 常规红标签外框 | 100×26，radius3，红alpha0.38，1px红边 | `u5l8kj4z_2rvYWPo3EMKx` |
| 常规红标签内部容器 | 84×22；不是外框高度 | `bqYiCzIfiJ8BtJX1-gDMY` |
| 小红标签外框 | 56×22，radius3，红alpha0.38，1px红边 | `LOi51u2qJoWht0skIr8BL` |

标签宽随内容；不同大小变体不能统一为22px。开关12px圆角足以否定“全组件半径不得超过6px”的泛化，但并不授权把普通按钮改成药丸形。

## 5. 已查到的交互原文与适用范围

| 组件 | 原稿文本/可核实状态 | 来源 ID与范围 |
| --- | --- | --- |
| 多任务流 | “页签最多显示 7 个字，超出部分省略，悬停查看完整内容” | `fLY2LeOzPCXg54zdxVmw-`；限多任务页签，不等于所有导航或表格标题截为7字 |
| 按钮 | “用户通过 Click/Hover（鼠标）或者Enter/Space Bar（键盘）等方式与按钮进行交互，立即触发一个Action（行为）同时获得相应的反馈与结果。” | `kWcNo3kM2KxEzCuYTwk5I`；保留按钮键盘可操作及相应反馈，不把hover解释成提交业务操作 |
| 日期选择器 | “Active（默认展开为日期选项，未hover日期面板）” | `lKGMkD72mb7h8KA-urlMj`；描述一个已展开且未hover面板的状态，并非“未hover不展开”；不凭此改写实际开启触发逻辑 |
| 轻提示 | “Toast 组件最大宽度为 600px，在多语言或特殊场景下支持折行处理，超出两行的部分用省略号表示” | `IEvL8Iy6bveLTD20MBMms`；适用于Toast组件，现有系统保行为时先改外观，不重写提示队列 |
| Tooltip | “文字提示是一种文本标签，当鼠标悬停于某个元素时显示。目标是为这些元素提供轻量的文本解释。” | `ndFVatCmEnmiAD6T1t1w0`；顶部/底部/左侧/右侧/跟随鼠标分别有位置文本 |
| Tooltip位置 | “1. 顶部出现”“2. 底部出现”“3. 左侧出现”“4. 右侧出现”“5. 跟随鼠标出现” | `Sya1gk6IBL9wkssd2mash`、`utMAvdRiqp8e2I4rW3Mjr`、`wQvZoENpqZc8HzVSVZ2VC`、`XcyCeU7ty8fMUBwWPUB-R`、`Enu48hsUdwvMPgNSfxUoj`；完整Tooltip库可覆盖这些模式，普通页面不必制造五处提示 |
| Progress | “进度0-10%时数字位置出现在目前进度的右边区域” | `gWYqNG2zZuidZeSXwZEg6`；针对规范中的百分比内显变体，不自动改变所有图表和视频进度条 |
| Progress内显例 | 80%文字位于`progress>10% / progress`内部，12px，白alpha0.9 | `abhBSskq_py2BdVxNZuO2`；这是样例。原文未写一律居中，不由历史提示词补“居中”硬规则 |
| Collapse | “可以将较多或较复杂的内容进行分组，分组内容区可以折叠展开或隐藏。” | `LQUNUhRMTJSomUYJuVyej`；使用折叠组件时支持其行为，不把现有普通卡片强改折叠 |
| Steps | 样例明确“进行中”“已完成”“未进行” | `vXvhlbjAXmqbMsoAmzU-H`、`1TNtjKuZ-vsHin9nhFTHq`、`iVHXefGBGnFUZQZ1VtBTN`；步骤条有三态 |
| Pagination | 样例含“共 101 项数据”“10 条/页”“跳至…页” | `oowHpZpOYMGWDTnUdiX-9`、`4MOpauoTOXHt0Xwh_i6zS`、`nF_vyUm-CC8UXkCf_hcZA`；证明组成项，不能单凭样例推出全站fixed定位 |
| Anchor | “页面内的超级链接，用于跳转到页面内指定位置” | `gSE6ZoqgT3IA60VsYJB9w`；适用于锚点，不改普通路由链接含义 |

进度区另有“该样式的颜色修改未与开发同步”（`TGg5YG0gJ-8pzdEGT-hPs`），所以源稿与旧开发样式可能不同；应说明参考版本，不冒称二者早已同步。

## 6. 七类组件的源稿索引

以下是检索入口，不表示每个尺寸和行为都已全量提取。做该类组件时读取对应源图层及上方已核实项；缺失参数不得套用旧提示词猜值。

| 类别 | 原稿顶层组 | 组 ID |
| --- | --- | --- |
| 导航 | 顶部导航 | `HLbQ4C3K3c76r9HBfkL8j` |
| 导航 | 多任务流 | `foZd9oS5lkXNlhDI5wSgR` |
| 导航 | 页签栏 | `a3CeIlCkKc12oiBb_n0tg` |
| 导航 | 锚点 | `YMtrBWVqtfEEUJj7xlgbK` |
| 导航 | 步骤条 | `1vJj-dn_7mpQOxqCEMVie` |
| 导航 | 分页器 | `j9LjmYkKY0DiFFdHUmP2Q` |
| 入口/表单 | 按钮 | `QLwvtxAFHgAbSwADSEDPm` |
| 入口/表单 | 选择器 | `F3JSNCtsrNXXJsyGfPKxS` |
| 入口/表单 | 级联选择器 | `RejBVjZVyV1Q79qkTakl1` |
| 入口/表单 | 输入框 | `-Nq3qtQI234d1QkHsDWWm` |
| 入口/表单 | 表单 | `Qml9HAp2TWdAXcCMKxAKj` |
| 入口/表单 | 日期选择器 | `NIjNnijiHo80ZRE3qBFxH` |
| 选择控制 | 复选框 | `LwJHFu2VfMb1lF2S2Jky9` |
| 选择控制 | 单选框 | `re0bIQ7LDkAg1kcZy52p0` |
| 选择控制 | 开关 | `WifcN9_baFybJxs_2HRB8` |
| 反馈 | 轻提示 | `yGd4Sj4fWnc84lyLU-cKS` |
| 反馈 | 常驻提示 | `4WrZ1abSQ-Z6gvy2xm6PA` |
| 反馈 | 文字提示 | `P8hIDaCQnuTUxGN5qqZmX` |
| 数据展示 | 树结构 | `FuH6zevraPJdwitkVMWFX` |
| 数据展示 | 折叠面板 | `ufphuQQil2RiXR1_HcDf4` |
| 数据展示 | 进度条 | `6zy8TBhDGk4GmOQizMmEu` |
| 数据展示 | 标签 | `IIBklkg06LAWnRmgjkP9X` |
| 数据展示 | 徽标 | `hvqqN5ieWgpkhp14As2GK` |
| 图标 | 描边图标 | `8NKREfHIsMWGYgxIK-Pk-` |
| 图标 | 面性图标 | `hEAhubznSQkpHmVRfsaRm` |
| 图标 | Icons-filled | `-H1JZXwPJJQFi_fZDaeAM` |
| 复合通用模式 | 指标、详情、媒体、多级状态、弹窗 | 以第7节对应画板及局部图层 ID 定位 |

复合组件以画板实例定位，见下一节。图标存在描边、面性与填充三类；目前证据不支持把全部图标线宽固定1.5px，使用对应图形的实际stroke，不用字体图标字号反推线宽。

## 7. 八张画板的实例边界

| 源画板名（仅定位） | Frame宽×高 | artboard ID |
| --- | --- | --- |
| 运行管理-缺陷单管理-缺陷单处理 | 1920×3782 | `l2EilwiTc98LFxqLDxVON` |
| 工作票 | 1920×5280 | `E039uJVZtKAGTAIDO77bC` |
| 监盘总览 | 1920×1080 | `6871A789-8CE3-4740-B3D0-094000F15129` |
| 巡视点位 | 1920×1080 | `10B88356-E25A-4D81-89FA-C206670C3310` |
| 告警及检修建议1 | 1920×1080 | `94138765-605A-41A3-ACDE-C959A3232D6A` |
| 巡视报告 | 1920×1080 | `B21F9F1F-13D9-41B5-B165-DCA03B8EE4AD` |
| 安全哨兵 | 1920×1080 | `A356A790-D0E3-490E-8539-574C5CB58EB0` |
| 告警及检修建议（弹窗） | 1920×1080 | `57889E44-04D1-4D74-B94F-4C1C42F427E5` |

长页的可见底层填充是`#121E37`：缺陷单`TVg_bJ9vbXlHa-43CXYQ-`，工作票`Jx8DTCDEAFqDItFW2nce4`。相同深色并不意味着所有画板都只有一种填充：监盘/多媒体页有渐变、叠底和专属面板，不统一替换为历史`#182B4D`。

| 用途示例 | 原生图层证据 | 层 ID |
| --- | --- | --- |
| 长页卡片 | 1896×560，`#50B1F9` alpha0.12 | `gikbC3t8uxeoq7IyvXlGB` |
| 长页表头/行 | 308×46，表头`#25556F`；行`#112345` alpha0.8 | `Hj1V_VRexjuuE5xAiV8vl` / `0UEYXZmdwPxCRahZvLKml` |
| 工作票表格 | 529×46，表头`#25556F`；行`#112345` alpha0.9 | `io2TvU1b0DvLwDFvTvPlo` / `GwOHOflr03kReDbIP3VpN` |
| 多面板监盘容器 | 624.3646×316.0639，`#101F30` alpha约0.2193 | `4BB08131-6AE7-4091-AC14-8E7CEA8FCE00` |
| 列表/报告内容面板 | `#50B1F9` alpha0.08 | `AE428F6E-D09A-4F46-97DC-E15D1D7C8D14` / `2C1833A1-B7CD-4CC5-9A52-1CFE58DDB176` |
| 可见大弹窗外框 | 1783×916，`#101F30` alpha约0.393并叠渐变，1px `#5ECBFF`边框 | `AD3EBC59-247B-4D9C-86E0-F0AC25A0692E` |

旧小弹窗`D5D553B1-BB66-4AC1-9D7F-991922AC37A9`的祖先隐藏，不能当作当前可见弹窗规范。表格样例46px也不意味着全部表格必须46px；它反证历史“数据行严格40px”无法作为全稿事实。主题映射应按目标项目实际行高/内容验证。

## 8. 现有智能穿戴项目的适配边界

用户要求保留布局和流程；当前普通顶栏64px、侧栏202px及响应式缩放、大屏1672×941画布和指标展示尺寸均属于该项目的保留项。来源模板不能覆盖这些已确认要求。正文常用阶梯、控件状态和配色可精修，允许变更的控件尺寸须防止列表卡片、按钮、视频和地图被挤压。

登录40px主按钮可对应大按钮变体；大屏大数字保留适合展示的尺寸并标记项目映射。原生select、date、checkbox的样式控制范围依浏览器而异；如果保交互为首要要求，记录兼容方式，不能隐式引入新组件行为。

图表、Canvas、SVG与业务标签按现有数据语义接入统一颜色。对本稿未涵盖的系统界面，采用已核实基础色和可解释的组合，不伪造源稿图层ID或声称所有页面原样来自Sketch。

## 9. 已撤回的历史硬参数

完整对照见 [实施文档第4节](合并提示词.md)。本次所有原生颜色记录中，`#182B4D`、`#0E182D`、`#1C3863`、`#1F385C`均无精确匹配；现项目旧适配色`#17294A/#162847/#1E3760`也不是原始色块。没有匹配不证明近似色不能作为用户授权的新设计，但禁止将其标成“原稿精确参数”。

取消无证据的完整Light强制映射、Roboto、仅400/600、仅七档字号、固定24px大屏数字、全组件圆角≤6px、全部表格40px、固定Header/Sidebar和所有项目Starter交付要求。保留原A/B全文作为历史，不删除证据，也不重新执行历史文档中的任务指令。
