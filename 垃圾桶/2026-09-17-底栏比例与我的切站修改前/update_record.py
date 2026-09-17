from pathlib import Path
import re, hashlib, shutil, json
r=Path(r'C:/Users/qiyue/Desktop/开发项目'); b=r/'新版安卓端开发'; d=b/'开发任务拆分'
backup=r/'垃圾桶/2026-09-17-底栏比例与我的切站修改前'
e=d/'验收记录/T02-四栏比例与我的切站'
apk=r/'android代码/melhat_android-main/build/app/outputs/flutter-apk/app-debug.apk'
digest=hashlib.sha256(apk.read_bytes()).hexdigest()
notice='> **最新进度（2026-09-17）：** 用户已授权前三页底栏与第四页统一，现四页均为60dp；我的右上角厂站已改为切换按钮，进入原选站流程，通话中禁用。T02开发自验通过、待用户审核。此前“其他分支保持原高度”的记录仅指上轮基线。详见[本轮验收](%s)。\n\n'
files=list(d.glob('*.md'))+[b/x for x in ('00-文档说明.md','08-安卓统一视觉规范.md','10-安卓开发指南-预览图复刻与微调.md','11-安卓逐页开发说明与跳转保留表.md','12-安卓开发强限制与验收清单.md','我的页面开发说明.md')]
modified=[]
for p in files:
    s=p.read_text(encoding='utf-8-sig'); orig=s
    if p.name.startswith(('T02-','01-任务','00-总','05-任务')) or '60dp' in s or p.name=='00-文档说明.md':
        href=('验收记录/' if p.parent==d else '开发任务拆分/验收记录/')+'T02-四栏比例与我的切站/说明.md'
        title,rest=s.split('\n',1);s=title+'\n\n'+notice%href+rest.lstrip('\n')
    if p.name=='01-任务总表与执行顺序.md':
        s=s.replace('| 4 | T13—T16；最新我的页已部署雷电 |','| 5 | T02、T13—T16；已部署雷电 |').replace('| 部分完成 | 4 | T02、T17、T47、T48 |','| 部分完成 | 3 | T17、T47、T48 |')
        s=s.replace('4/48项（8.3%，仅任务数口径），另4项部分完成','5/48项（10.4%，仅任务数口径），另3项部分完成')
        s=re.sub(r'^\| \[T02 .*$', '| [T02 四栏底导航](T02-四栏底导航.md) | 无 | 四页NavigationBar统一60dp、内容区比例 | 待用户审核（开发自验通过） | 用户最新比例要求已交付；不改图标和标签 |',s,flags=re.M)
        s=s.replace('先补T02剩余对照，再逐项','T02已交付，接着逐项').replace('先审核T13—T16 → T02剩余 →','先审核T02、T13—T16 →')
    if p.name=='05-任务进度与续作安排.md':
        s=re.sub(r'^\| T02 .*$', '| T02 | 四分支均60dp，原图标／标签／红点保留；前三页内容区增高20dp，实际截图及切换通过 | 待用户审核，不再安排其他分支比例实施 |',s,flags=re.M)
        s=re.sub(r'推荐从T02剩余部分开始：.*?(?=\n\n之后T03)', 'T02已按用户最新要求开发并部署，自验通过。后续建议从T03现场页头开始，当前不自动启动后继。',s,flags=re.S)
    if p.name=='00-总指挥与总限制.md':
        s=s.replace('T02、T17、T47、T48：部分完成','T17、T47、T48：部分完成').replace('T13—T16：当前范围已开发','T02、T13—T16：当前范围已开发')
        s=s.replace('6. 底栏只在我的分支已设60dp，其余保持原值。T02剩余工作需先举出具体比例差异，不整应用统一缩高。','6. 底栏四分支已按用户要求统一60dp，保持原图标、文字和顺序；未授权的新比例调整仍需明确到具体区域。')
        s=s.replace('再补T02剩余比例检查，随后逐项','随后逐项').replace('T02其他分支比例','T02其他分支比例（现已完成）')
    if p.name=='T02-四栏底导航.md':
        s=re.sub(r'- \*\*状态：\*\* .*','- **状态：** 待用户审核（开发自验通过）。四页底栏统一60dp，前三页可见内容区增高20dp；已覆盖安装雷电并逐页截图。证据见本页最新进度链接。',s,count=1)
        s=s.replace('保留当前我的分支60dp高度及其他分支原值；逐个切换Tab再返回，记录实际比例差异，仅对本次授权区域微调，不自动全局改高。','将前三页底栏统一为我的当前60dp高度；四栏图标、文字、红点、默认页与goBranch保持；内容区自然扩展，不缩放原卡片。')
        for i in range(1,4):s=s.replace(f'- [ ] **步骤{i}：',f'- [x] **步骤{i}：')
    if p.name=='00-文档说明.md':
        s=s.replace('T13—T16开发自验通过、待用户审核；T02、T17、T47、T48部分完成','T02、T13—T16开发自验通过、待用户审核；T17、T47、T48部分完成')
    if p.name=='我的页面开发说明.md':
        s=s.replace('仅我的分支高度改为60dp，其他分支仍用原值','四分支高度现已按用户后续要求统一为60dp')
        s=s.replace('| 我的装备 | 本人装备详情 |','| 右上角当前厂站 | 原厂站选择页 | 选择成功后按既有逻辑回现场；我的按钮与身份卡同步更新，通话中禁用 |\n| 我的装备 | 本人装备详情 |')
    if s!=orig:
        dest=backup/p.relative_to(r);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
        p.write_text(s,encoding='utf-8');modified.append(p.relative_to(r).as_posix())

(e/'说明.md').write_text(f'''# 四栏比例与我的厂站按钮验收

日期：2026-09-17。开发自验通过，已部署雷电，待用户审核。

## 修改与原因

原前三页NavigationBar使用默认80dp，第四页为60dp，导致可见内容区和底栏占比不同。本轮四页统一60dp；前三页内容区自然增加20dp。原图标、标签、未读点、点击分支和默认现场保留；没有缩放整页卡片或背景。

我的右上角厂站原是Text，现为TextButton，带下拉箭头、最少48dp点击高度和长名称省略，仍位于原头图右上角。点击进入已有/sites，沿用/api/v1/me/current-site的PUT与服务端确认；通话中和忙碌时禁用，不另造厂站数据。原设置内切站入口仍可用。

生产代码仅lib/wear/app.dart和lib/wear/mine_page.dart；新增行为回归合入test/wear_mine_reference_test.dart。图片与其他页面源文件未改。

## 验证

- 新测试在修改前明确复现80dp与60dp不一致；修改后验证四分支高度、点击、通话限制、真实切站接口参数和返回我的的新站名。
- 8项回归通过，含原菜单／账号操作与普通／大字号；静态检查No issues found。
- 新测试使用独立测试用户，避免共用事件草稿静态写入队列影响后续退出测试；未改变生产会话逻辑。
- 雷电四页实际截图已逐页查看。底栏均从y=1740至1920，1080×1920／3倍密度，即60dp。
- 实机路径：我的右上角→厂站列表→演示厂站B→现场→我的，按钮与资料卡均显示B；随后经同入口恢复演示厂站A。当前停在我的页。
- 构建android-x64/debug成功，覆盖安装Success；API_BASE_URL=http://127.0.0.1:18084，沿用ADB reverse与Docker后端。

APK SHA256：`{digest}`。

## 截图

- [现场](01-现场.png)、[通讯](02-通讯.png)、[消息](03-消息.png)、[我的](04-我的.png)
- [厂站选择页](05-厂站选择.png)、[切至B后我的](06-切站B.png)
- [测试日志](tests.log)

## 进度与回退

T02由部分完成改为开发自验通过、待用户审核。T13—T16继续保留已有交付，其中我的页头追加本轮切站按钮。其余任务不提前开始；有效48项中5项待审核、3项部分完成、40项未开始。

本次修改前代码、测试、文档和APK位于项目根相对路径：垃圾桶/2026-09-17-底栏比例与我的切站修改前，按原相对路径保留。回退只恢复本次文件，不能恢复亮暗开关或整仓重置。
''',encoding='utf-8')
(e/'文件记录.json').write_text(json.dumps({'apkSha256':digest,'documentationUpdated':modified,'productionFiles':['android代码/melhat_android-main/lib/wear/app.dart','android代码/melhat_android-main/lib/wear/mine_page.dart']},ensure_ascii=False,indent=2),encoding='utf-8')
print('Saved evidence and updated progress.')
