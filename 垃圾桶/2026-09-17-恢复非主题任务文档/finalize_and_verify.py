from pathlib import Path
import re,json,hashlib,collections
ROOT=Path(r'C:/Users/qiyue/Desktop/开发项目');BASE=ROOT/'新版安卓端开发';OUT=BASE/'开发任务拆分'
OLD=ROOT/'垃圾桶/2026-09-17-取消明暗规划/新版安卓端开发';AUDIT=ROOT/'垃圾桶/2026-09-17-恢复非主题任务文档'
def edit(p, pairs):
    t=p.read_text(encoding='utf-8')
    for a,b in pairs.items():t=t.replace(a,b)
    p.write_text(t,encoding='utf-8')
edit(BASE/'11-安卓逐页开发说明与跳转保留表.md',{'深浅分别采用原图各自的图片底色和边框。':'图片底色和边框按浅00校准。当前本人详情无底栏，与图00的差异见任务04登记，不能直接当作已完成或默默改壳层。'})
edit(BASE/'10-安卓开发指南-预览图复刻与微调.md',{'本輪':'本轮','| 编号 | 页面 | 浅色原图 | 深色原图 |':'| 编号 | 页面 | 当前浅色原图 | 历史深色资料（不实施） |'})
edit(BASE/'03-新版安卓端UI开发文档.md',{'组件和主题':'组件样式','；主题与登录、路由和业务状态解耦':'；原登录、路由与业务状态保持','雷电导航与主题':'雷电导航与页面'})
edit(BASE/'07-安卓页面职责与冲突整改方案.md',{'- 深浅主题覆盖登录、所有主子页面、弹窗、键盘区域、地图容器和通话控件；字号放大仍可操作，状态不只靠颜色。':'- 登录、主子页面、弹窗、键盘区域、地图容器和通话控件均需可读；字号放大仍可操作，状态不只靠颜色。'})
p=BASE/'09-安卓整改重点总结-审核预览.md';t=p.read_text(encoding='utf-8')
t=re.sub(r'## 3\. 统一风格与一键切换.*?(?=## 4\.)','''## 3. 视觉规则修订说明

本旧稿的整体换肤建议此前已被否定；外观切换现已取消。其他功能分析恢复供查阅，当前视觉以10—12、最新我的页说明和任务总览为准，不重新执行本稿旧布局。

''',t,flags=re.S).replace('帮助、外观；','帮助；')
p.write_text(t,encoding='utf-8')

# 恢复08原先非切换的页面映射、排版等分析，保留历史失效标记，避免误删其他内容。
p=BASE/'08-安卓统一视觉规范.md';t=p.read_text(encoding='utf-8')
raw=next(OLD.glob('08-*.md')).read_text(encoding='utf-8-sig');kept=[]
for m in re.finditer(r'^## (\d+)\..*?(?=^## \d+\.|\Z)',raw,re.M|re.S):
    if int(m[1]) in (2,3,4,5):kept.append(m[0])
historical='\n\n'.join(kept)
historical=historical.replace('### 4.1 所有主题共用壳层','### 4.1 旧壳层分析（已失效）')
historical=historical.replace('主题设置及通讯诊断','通讯诊断').replace('返回、页面标题、主题切换','返回、页面标题').replace('品牌与主题切换','品牌')
historical=historical.replace('主题切换不触发厂站切换、不重新选择。','')
historical=historical.replace('不能由主题切换触发关闭','不能因页面刷新关闭')
historical=historical.replace('不借主题逻辑隐式清理','不隐式清理')
historical=historical.replace('，主题按钮位置固定','').replace('返回及主题入口','返回入口')
historical=historical.replace('品牌与主题 →','品牌 →').replace('密码不因切主题清空或暴露','密码不因页面刷新清空或暴露')
historical=historical.replace('外观行显式显示当前主题；','')
t=t.replace('## 原规范非切换部分（保留资料）','''## 原规范非切换部分（保留资料）

以下恢复原九组页面映射、冲突分析、排版和状态规范。旧三入口、暖石与去插画等建议仍已失效，不得据此修改代码；保留原分析是为了查阅，当前执行页首规则与10—12。

'''+historical)
t=t.replace('；主题仍可切换','').replace('通过主题缓存暴露旧账号数据','通过旧缓存暴露其他账号数据').replace('演示标识随切主题消失','演示标识随页面刷新消失').replace('主题按钮朗读当前状态与将执行动作；','').replace('SOS弹层期间切换；','SOS弹层期间打开子页并返回；')
p.write_text(t,encoding='utf-8')

for p in OUT.glob('T*.md'):
    edit(p,{'返回页面和返回后':'返回后','返回页面及返回保留选择':'打开子页再返回仍保留选择','返回页面输入':'返回后输入保留','筛选返回页面':'筛选后返回','_profileRow与身份WearCard':'_profileRow与当前白色身份资料卡'})
edit(OUT/'01-任务总表与执行顺序.md',{'_profileRow与身份WearCard':'_profileRow与当前白色身份资料卡'})
# 已自验项继续保留检查清单，但不要求重新构建才能审阅旧成果。
for n in (13,14,15,16):
    p=next(OUT.glob(f'T{n:02d}-*.md'));t=p.read_text(encoding='utf-8')
    t=t.replace('## 验收步骤','''## 验收步骤

以下保留为审核清单，已执行证据统一链接[原始验收记录](../我的页面整改验收/验收说明.md)。本轮不重复测试或部署；用户审核结论尚未写入。若之后有具体返修，才重新运行受影响检查并追加新证据。
''')
    t=t.replace("test --no-pub test/wear_app_test.dart","test --no-pub test/wear_mine_reference_test.dart test/wear_app_test.dart")
    p.write_text(t,encoding='utf-8')

# 记录当前待办说明，作为文档修订记录，不创建UI已验收假证据。
report=OUT/'06-文档恢复与修订记录.md'
report.write_text('''# 文档恢复与修订记录

日期：2026-09-17。本轮根据用户纠正，只取消亮暗功能，恢复其余开发文档，重新登记任务进度。

## 恢复范围

- T02—T49共48份任务书全部恢复。原非主题功能步骤、文件定位、测试建议、对象参数与回退要求保留。
- 00总指挥、01总览、02验收、03衔接、04例外及目录README恢复修订；新增05进度与本记录。
- 父目录01—04、07—12恢复；其中旧分析仍标历史失效，不能重新执行三栏／暖石大改。08保留非切换的映射、排版、可读性和状态资料并改名。
- 只取消T01施工书与亮暗相关代码契约、背景切换、偏好保存、成套深色生成和双主题验收要求。T33登录背景、T49弹层空态和系统栏任务保留并改名。
- 已部署我的页面不回退；T13—T16归为待用户审核，T02、T17、T47、T48部分完成，其他40项未开始。

## 文件名变化

| 原相对路径（新版安卓端开发内） | 恢复后的相对路径 |
| --- | --- |
| 开发任务拆分/03-主题与素材衔接说明.md | 开发任务拆分/03-局部视图与素材衔接说明.md |
| 开发任务拆分/T33-登录页头与深色背景.md | 开发任务拆分/T33-登录页头与背景.md |
| 开发任务拆分/T49-全局弹层与系统主题收口.md | 开发任务拆分/T49-全局弹层与系统栏收口.md |
| 08-安卓统一视觉与明暗主题规范.md | 08-安卓统一视觉规范.md |

完整来源、目标、哈希及修改前备份位于项目根目录的 `垃圾桶/2026-09-17-恢复非主题任务文档/`。旧T01专用施工文件和证据仍在原垃圾桶归档中，未恢复至任务目录。原始18张预览图及客户Word保持不变。

本轮只改文档，未构建或部署，不改变模拟器当前安装的我的页版本。
''',encoding='utf-8')

files=list(BASE.glob('*.md'))+list(OUT.glob('*.md'))+[BASE/'我的页面整改验收/验收说明.md']
errors=[];broken=[]
for p in files:
    s=p.read_text(encoding='utf-8-sig')
    for target in re.findall(r'(?<!!)\[[^\]\n]+\]\(([^)]+)\)',s):
        target=target.strip('<>').split('#')[0]
        if not target or re.match(r'^(https?:|app:|codex:)',target):continue
        # 历史源码链接中的:行号
        target=re.sub(r':\d+$','',target)
        q=Path(target) if re.match(r'^[A-Za-z]:',target) else p.parent/target
        if not q.exists():broken.append({'file':p.relative_to(ROOT).as_posix(),'target':target})
tasks=sorted(OUT.glob('T*.md'));ids=[int(p.name[1:3]) for p in tasks]
if ids!=list(range(2,50)):errors.append('Task coverage mismatch')
counts=collections.Counter();deps={}
for p in tasks:
    s=p.read_text(encoding='utf-8');n=int(p.name[1:3])
    st=re.search(r'- \*\*状态：\*\* ([^。]+)',s)[1];counts[st]+=1
    if re.search(r'\bC1\b|T01-外观开关.md|preview_appearance|wear.preview.appearance|生成.*深色|切主题|切换主题',s):errors.append(f'Cancelled dependency/instruction: {p.name}')
    nums=[int(x) for x in re.findall(r'- \[[ x]\] \*\*步骤(\d+)：',s)]
    if nums!=list(range(1,12)):errors.append(f'Steps mismatch: {p.name} {nums}')
    deps[n]=[int(x) for x in re.findall(r'\[T(\d+)\]',re.search(r'- \*\*依赖：\*\* (.*)',s)[1])]
    if any(x not in ids or x==n for x in deps[n]):errors.append(f'Invalid dependency: {p.name}')
overview=(OUT/'01-任务总表与执行顺序.md').read_text(encoding='utf-8')
if len(re.findall(r'^\| \[T\d\d ',overview,re.M))!=48:errors.append('Overview count mismatch')
if counts!={'未开始':40,'部分完成':4,'待用户审核（开发自验通过）':4}:errors.append(f'Status count mismatch {counts}')
for n in ids:
    stack=[]
    def visit(x):
        if x in stack:raise ValueError(f'Dependency cycle {stack} -> {x}')
        stack.append(x)
        for d in deps[x]:visit(d)
        stack.pop()
    visit(n)
before=json.loads((AUDIT/'保护文件修改前.json').read_text(encoding='utf-8'))
changed=[name for name,h in before.items() if not (ROOT/name).exists() or hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=h]
if changed:errors.append('Protected files changed')
manifest=json.loads((AUDIT/'恢复清单.json').read_text(encoding='utf-8'))
manifest.append({'originalRelativePath':None,'restoredRelativePath':report.relative_to(ROOT).as_posix()})
for item in manifest:item['sha256']=hashlib.sha256((ROOT/item['restoredRelativePath']).read_bytes()).hexdigest()
(AUDIT/'恢复清单.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
result={'tasks':len(tasks),'statusCounts':dict(counts),'checkedDocs':len(files),'protectedFilesUnchanged':len(before)-len(changed),'changedProtectedFiles':changed,'brokenLinks':broken,'errors':errors}
(AUDIT/'核对结果.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2))
if errors:raise SystemExit(1)
