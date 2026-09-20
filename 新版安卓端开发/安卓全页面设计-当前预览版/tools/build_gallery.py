"""Build an offline gallery from current Flutter rendering captures.
No Android production file is modified by this builder.
"""
import json, hashlib, shutil, math, subprocess
from pathlib import Path
from datetime import datetime
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[1]
ROOT = OUT.parents[1]
ANDROID = ROOT / 'android代码/melhat_android-main'
REF = OUT.parent / '安卓全页面设计-浅色多彩版'

# id, current title, section, parent, actual kind, entry, implementation note
rows = [
('01','欢迎登录','账号',None,'页面','启动应用','登录表单和验证码布局已实现；展示使用本地演示身份。'),
('02','找回登录权限','账号','01','弹层','登录 → 登录遇到问题','当前仅关闭弹层并提示联系管理员，未调用密码重置接口。'),
('03','选择工作厂站','账号','01','页面','登录后选择厂站；现场或我的也可切站','读取授权厂站并执行切站的代码已实现；此处为演示厂站。'),
('04','现场','现场','03','主页面','底部导航 → 现场','当前工作台：作业、我的装备和现场入口；保留最新顶部及底栏比例。'),
('05','作业任务','现场','04','子页面','现场 → 作业任务','作业列表和详情跳转已实现，数据为示例。'),
('06','作业详情','现场','05','子页面','作业任务 → 任务；现场 → 查看作业','包含作业信息、人员、装备核查和相关事件；当前子页隐藏底部导航。'),
('07','现场人员','现场','04','子页面','现场 → 人员','人员列表、姓名搜索和详情入口已实现。'),
('08','人员详情','现场','07','子页面','现场人员 → 人员；作业详情 → 成员','展示人员资料、装备和相关事件入口。'),
('09','失去监护人员','现场','04','子页面','现场 → 失去监护人员','根据作业装备核查聚合；当前示例均正常，因此展示真实空态。'),
('10','设备台账','现场','04','子页面','现场 → 设备','设备列表及类型/状态筛选已实现。'),
('11','设备详情','现场','10','子页面','设备台账 → 设备；人员详情 → 装备','包含状态、能力及绑定信息，通信入口按设备能力显示。'),
('12','设备状态异常','现场','11','状态','设备详情 → 离线设备状态','同一设备详情组件，注入离线示例；不是新增独立页面。'),
('13','轨迹回放','现场','04','页面 · 部分异常','现场 → 轨迹；人员详情 → 轨迹','展示原页面的未选择人员状态。当前源码在选中人员、轨迹为空时预先构造回放内容，触发 ArgumentError；原始诊断截图另行保留，轨迹播放未标为验收完成。'),
('14','电子围栏','现场','04','子页面','现场 → 围栏','围栏列表已实现；本展示使用本地示例围栏。'),
('15','围栏详情','现场','14','子页面','电子围栏 → 围栏','规则和边界展示已实现；示例未提供 geometry，按现有页面显示无边界数据。'),
('16','轨迹查询 · 选择人员','现场','13','状态','轨迹入口 → 搜索并选择人员','轨迹页的人员选择状态，尚未触发空轨迹异常。'),
('17','通讯','通讯','03','主页面','底部导航 → 通讯','人员/设备选择及通信功能区已实现；仅使用本地数据。'),
('18','语音通话','通讯','17','状态','通讯 → 选择装备 → 手机呼叫','原通信组件的演示会话状态，不连接真实 RTC 或麦克风。'),
('19','视频通话','通讯','17','状态','通讯 → 选择装备 → 视频呼叫','原通信组件的视频状态；示例画面不是实时视频。'),
('20','语音播报','通讯','17','功能区','通讯 → 语音播报 → 选择装备','原通讯页内的文字播报表单；本地示例不会向设备下发指令。'),
('21','通话记录','通讯','17','功能区','通讯 → 选择装备 → 下滑查看记录','通话历史位于同一个通讯页面底部，并非独立路由。'),
('22','消息','消息','03','主页面','底部导航 → 消息','使用当前连续滚动列表与紧凑筛选区；异常和 SOS 分别进入对应详情。'),
('23','筛选事件','消息','22','弹层','消息 → 筛选','底部筛选弹层，保留实际字段与按钮。'),
('24','事件详情 · 更多处置与记录','消息','25','展开状态','异常核验 → 更多处置与记录','事件详情由异常核验/SOS共用；本项展示展开的原始处置与记录区。'),
('25','异常核验','消息','22','子页面','消息 → 普通事件；作业详情 → 相关事件','核验表单已实现；照片功能目前为示例添加/预览/删除，不上传服务器。'),
('26','SOS 协助','消息','22','子页面','消息 → SOS 事件','SOS 详情已实现；示意地图、附件及协助组体验仍为示例，协助组服务未接入。'),
('27','转交事件','消息','24','弹层','事件更多处置 → 转交','同站值班人员与原因表单已实现；此处仅展示本地演示操作。'),
('28','关联作业','消息','24','弹层','待确认关联的事件 → 确认关联任务','仅 taskMatch=pending 且有权限时显示；截图使用这一条件的示例事件。'),
('29','事件处置','消息','26','展开状态','已认领的 SOS → 更多处置与记录','展示原始处置说明表单和操作区，使用已认领的 SOS 示例，保留操作权限和事件状态约束。'),
('30','我的','我的','03','主页面','底部导航 → 我的','当前问候、账号资料、通讯服务、装备、设置与账号操作。'),
('31','我的装备','我的','30','子页面','我的 → 我的装备；现场 → 查看全部','使用当前紧凑装备页，保留三类装备及绑定历史入口。'),
('32','绑定历史','我的','31','弹层','我的装备 → 绑定历史','当前实现为底部弹层，参考稿的“历史领用记录”在这里对应绑定历史。'),
('33','通讯服务','我的','30','子页面','我的 → 查看状态','接警连接、通知权限、账号及绑定状态；截图未启动真实推送服务。'),
('34','设置','我的','30','子页面','我的 → 设置','设置保留切站和交接记录；没有亮暗切换。'),
('35','值班交接 · 确认接班','我的','34','弹层','设置 → 待接班记录 → 确认接班','交接记录和确认弹层已实现；为显示弹层注入一条待接班示例。'),
('36','帮助与反馈','我的','30','子页面','我的 → 帮助与反馈','使用帮助及复制诊断信息已实现，没有独立意见提交服务。'),
('37','通知权限未开启','我的','33','状态','通讯服务 → 通知权限状态','与通讯服务共用页面；展示未授权状态，不代表真实手机权限。'),
('38','退出登录','我的','30','弹层','我的 → 退出登录','当前退出确认弹层；确认后清理会话并回到登录。'),
('39','页面空态','通用','07','状态','现场人员 → 无匹配姓名','由人员列表零结果触发的原始空态组件。'),
('40','网络异常','通用','10','状态','设备列表 → 请求失败','通过演示适配器注入 503，展示原页面失败/重试状态。'),
('41','加载中','通用','10','状态','设备列表 → 等待响应','保留请求未完成状态，展示原始加载组件。'),
('42','切换账号','我的','30','弹层','我的 → 切换账号','补充与退出登录分开的实际确认弹层。'),
]
cross = {'03':['04','30','34'],'06':['04'],'08':['06'],'11':['08','31'],'13':['08'],'17':['08','11','25','26'],'22':['04','06','08'],'31':['04'],'24':['26']}
source = {**{i:'auth_pages.dart' for i in ['01','02','03']}, **{i:'queries/'+n+'.dart' for i,n in [('04','workbench'),('05','tasks'),('06','tasks'),('07','people'),('08','people'),('09','supervision'),('10','devices'),('11','devices'),('12','devices'),('13','tracks'),('14','fences'),('15','fences'),('16','tracks'),('31','my_equipment_page'),('32','my_equipment_page'),('39','people'),('40','devices'),('41','devices')]},**{str(i):'communications/communications_page.dart' for i in range(17,22)},**{str(i):'events/events_page.dart + events/event_reference_view.dart' for i in range(22,30)},**{str(i):'mine_page.dart' for i in [30,33,34,35,36,37,38,42]}}

def build():
    (OUT/'页面图片').mkdir(exist_ok=True)
    (OUT/'pages').mkdir(exist_ok=True)
    items=[]
    refs={x['id']:x for x in json.loads((REF/'manifest.json').read_text('utf-8'))}
    for id,title,group,parent,kind,entry,note in rows:
        capdir=OUT/'captures'/id
        record=json.loads((capdir/'capture.json').read_text('utf-8'))
        frames=record['frames']; first=Image.open(capdir/frames[0]['file']).convert('RGB')
        scale=record['pixelRatio']; w,h=first.size
        # Each next strip starts exactly after the previous content endpoint.
        # Fixed top/bottom regions appear once; originals remain available.
        top=max(0,round(frames[0]['top']*scale)); bottom=min(h,round((frames[0]['top']+frames[0]['height'])*scale))
        strips=[first.crop((0,0,w,bottom))] if len(frames)>1 else [first]
        previous=frames[0]
        for frame in frames[1:]:
            image=Image.open(capdir/frame['file']).convert('RGB')
            delta=round((frame['offset']-previous['offset'])*scale)
            if delta>0: strips.append(image.crop((0,bottom-delta,w,bottom)))
            previous=frame
        if len(frames)>1: strips.append(Image.open(capdir/frames[-1]['file']).convert('RGB').crop((0,bottom,w,h)))
        result=Image.new('RGB',(w,sum(s.height for s in strips)), '#eef5fc'); y=0
        for strip in strips: result.paste(strip,(0,y)); y+=strip.height
        result.save(OUT/'页面图片'/f'{id}.jpg',quality=92,subsampling=0)
        thumb=first.copy(); thumb.thumbnail((540,924)); thumb.save(OUT/'页面图片'/f'{id}-首屏.jpg',quality=88)
        item=dict(id=id,title=title,group=group,parent=parent,kind=kind,entry=entry,note=note,source='lib/wear/'+source[id],otherParents=cross.get(id,[]),referenceTitle=refs.get(id,{}).get('title','补充状态'),image=f'页面图片/{id}.jpg',thumb=f'页面图片/{id}-首屏.jpg',width=w,height=result.height,frames=[dict(**f,url=f"captures/{id}/{f['file']}") for f in frames],long=len(frames)>1,issue=id=='13')
        items.append(item)
    hashes={str(p.relative_to(ANDROID)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ANDROID/'lib/wear').rglob('*.dart'))}
    for p in (ANDROID/'lib/web_preview').glob('*.dart'): hashes[str(p.relative_to(ANDROID)).replace('\\','/')]=hashlib.sha256(p.read_bytes()).hexdigest()
    data={'generatedAt':datetime.now().isoformat(timespec='seconds'),'sourceCommit':subprocess.check_output(['git','rev-parse','--short','HEAD'],cwd=ROOT,text=True).strip(),'sourceType':'当前工作区（含未提交修改）','captureMethod':'Flutter 原组件渲染；360×616 逻辑像素，3倍输出；本地 Noto CJK 字体。业务数据均为示例；非雷电系统截图。','items':items}
    (OUT/'manifest.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),'utf-8')
    (OUT/'manifest.js').write_text('window.PREVIEW = '+json.dumps(data,ensure_ascii=False)+';','utf-8')
    (OUT/'源码校验.json').write_text(json.dumps(hashes,ensure_ascii=False,indent=2),'utf-8')
    relation_lines=['# 页面入口与当前实现对照','',f"生成时间：{data['generatedAt']}。源码基线：{data['sourceCommit']} + 当前工作区。所有业务数据为本地示例。",'',f"共 {len(items)} 个展示项，{sum(p['long'] for p in items)} 个长页面，{sum(len(p['frames']) for p in items)} 张分屏。编号 01–40 对应参考稿，41–42 为补充状态。",'','| 编号 | 当前页面 | 类型 | 主要父页面 | 其他入口 | 屏数 | 当前实现 |','| --- | --- | --- | --- | --- | --- | --- |']
    item_map={p['id']:p for p in items}
    for p in items:
        parent=f"{p['parent']} {item_map[p['parent']]['title']}" if p['parent'] else '应用启动'
        others='、'.join(f"{i} {item_map[i]['title']}" for i in p['otherParents']) or '—'
        relation_lines.append(f"| {p['id']} | [{p['title']}](pages/{p['id']}.html) | {p['kind']} | {parent} | {others} | {len(p['frames'])} | {p['note']} |")
    relation_lines+=['','## 来源与定位','']
    relation_lines += [f"- {p['id']} {p['title']}：`{p['source']}`；入口：{p['entry']}。" for p in items]
    (OUT/'页面入口关系.md').write_text('\n'.join(relation_lines)+'\n','utf-8')
    template=(OUT/'index.html').read_text('utf-8')
    for p in items:
        page=template.replace('<head>','<head><base href="../">').replace('<body>','<body data-page="'+p['id']+'">').replace('<title>安卓当前开发预览 · ROLLING</title>','<title>'+p['title']+' · 安卓当前开发预览</title>')
        (OUT/'pages'/f"{p['id']}.html").write_text(page,'utf-8')
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',25)
    small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',17)
    board=Image.new('RGB',(1920,math.ceil(len(items)/6)*435+140),'#eef5fc'); d=ImageDraw.Draw(board)
    d.text((35,25),'ROLLING · 安卓当前开发页面总览',font=font,fill='#17385f')
    d.text((35,70),'当前工作区原组件渲染 / 示例数据 / 完整长图与父子关系请打开 index.html',font=small,fill='#55738f')
    for i,p in enumerate(items):
        x=30+(i%6)*315;y=130+(i//6)*435
        im=Image.open(OUT/p['thumb']); im.thumbnail((210,360));board.paste(im,(x,y))
        title=p['title'][:15];d.text((x,y+368),p['id']+' '+title,font=small,fill='#17385f')
        d.text((x,y+396),f"{p['kind']} · {len(p['frames'])} 屏",font=small,fill='#55738f')
    board.save(OUT/'页面总览.jpg',quality=90)
    print(f"Built {len(items)} items; {sum(p['long'] for p in items)} long pages; {sum(len(p['frames']) for p in items)} frames")

if __name__=='__main__':build()
