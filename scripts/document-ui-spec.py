"""Regenerate the human-readable traceability tables without changing application code."""
import csv
import importlib.util
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'shared/ui-spec'
spec = importlib.util.spec_from_file_location('extract', Path(__file__).with_name('extract-ui-spec.py'))
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)

components = json.loads((OUT/'evidence/components.json').read_text(encoding='utf-8'))
aliases = json.loads((OUT/'icon-aliases.json').read_text(encoding='utf-8'))
icons = json.loads((OUT/'evidence/icons.json').read_text(encoding='utf-8'))
semantic = {
    'drop-line':'血氧指标使用同库环形图标', 'oxygen':'血氧指标使用同库环形图标',
    'inbox-2-line':'装备资产使用同库控制平台图标', 'Box':'装备资产使用同库控制平台图标',
    'mic-off-line':'关闭话筒使用同库静音图标', 'person-location-fill':'人员位置使用同库实心人员图标',
    'shape-line':'围栏使用同库矩形图标', 'shield-user-line':'人员安全使用同库已核验人员图标',
    'antenna':'通信指标使用同库无线网络图标', 'factory':'厂站使用同库建筑图标',
    'worker':'作业人员使用同库人员图标', 'pulse-line':'趋势使用同库折线图标',
    'heart-pulse-line':'生命体征使用同库心形图标', 'voiceprint-line':'语音使用同库声音图标',
    'stop-fill':'停止使用同库实心停止圆形图标', 'pause-fill':'暂停使用同库实心暂停圆形图标',
    'chevron-left-double':'原稿向上双箭头旋转 -90°', 'chevron-right-double':'原稿向下双箭头旋转 -90°',
}
with (OUT/'icon-mapping.csv').open('w',encoding='utf-8-sig',newline='') as f:
    w=csv.writer(f);w.writerow(['applicationName','sourceName','sourceLayerId','sourcePath','sourceGeometrySha256','mapping'])
    for alias,name in aliases.items():
        i=icons[name]
        w.writerow([alias,name,i['id'],i['path'],i['geometrySha256'],semantic.get(alias,'同义命名；使用原稿对应矢量')])

rules=[
 ('主按钮','默认/悬停/按下/禁用',['4HFYwkQ-FC6Gp4FBgQYsn','xXg75oJxJl_WGdmtTTFuN','wFGy3DfrBzcg5MhEENjKM','A2OOwHqxrDM9sRhfmcp8W'],'.btn.primary / .button.primary','32px / 14px / 22px；四态独立颜色'),
 ('按钮规格','紧凑/常规/大',['CkstYJO3Hiokoedmyf64Z','4HFYwkQ-FC6Gp4FBgQYsn','t4_AdXg-GSXV4b5IZwBEI'],'按钮 small / 默认 / 登录主操作','24/32/40px；紧凑文字12px，常规及大按钮14px'),
 ('输入框','默认',['WH_CO_Ryr9t91AmzsRExp'],'AppInput / 原生 input / UiDatePicker','32px高，4px圆角；透明底；边框#83F6FD alpha .35'),
 ('下拉选项','默认/悬停/选中',['vtlVFKvKZ4Sh3tlRTk-cz','I0Y7nDcT1zSenZWCzO4cL','VThA-ge8SrGF2fZV7JafD'],'UiSelect','28px行；6px容器内边距；2px行距；4px圆角'),
 ('日期面板','展开',['YkUSGQ69TR712LBDSGBvs'],'UiDatePicker','312px日历；日期时间504px；单元32px高；16px内边距'),
 ('文字提示','展开',['D1Y8tE-ndrB_DsfKhfE7C'],'tooltip.js','.9黑色；4px圆角；4px 8px内边距；14/22px'),
 ('复选框','选中/未选中',['Zb7zYWwChCrTirxpNeCbu','7u3yvNPyer5rrFwTvhwHX'],'input[type=checkbox]','16px正方形；1px边框；原稿勾选矢量'),
 ('单选框','未选中/选中',['VgJEMc5_0dxx6uZbIw0AP','Ult4uE8ZaeAL4tmb-ZpLm'],'input[type=radio]','16px圆形；8px内圆'),
 ('开关','关/开/禁用',['g__GhdR1d9dK-EQIOHb7m','i8ZDtnIG6HRxJI076cCjY','3k6gBRbiF_I2Ti3k5B7Nc'],'UiSwitch','32×20px；16px滑块；2px边距'),
 ('标签','常规/紧凑',['u5l8kj4z_2rvYWPo3EMKx','LOi51u2qJoWht0skIr8BL'],'tag / badge','26/22px，3px圆角；红色组件底透明度.38优先于色板.25'),
 ('页签','选中/默认',['UXsXflFbJ-yR1M6B338yu','BUcZpmTAf5eb9NRwjPINo','Ttmhf3aXtHv0A79QXBwan'],'AppTabs / workspace-tabs','分别保留面板页签和下划线页签规格'),
 ('分页','常规',['d8SUk0URGgv8LkX31aPFB','Hstb7oae8Z0KvRQFj_wp2'],'pagination / UiSelect','32px高；选择器4px圆角；沿用现有翻页行为'),
 ('树','默认/选中',['7u3yvNPyer5rrFwTvhwHX','VBXfZnPfUAK0sWGJfSe0s'],'tree-branch / 原生权限复选框','保留树层级，复选框16px，选中使用规范强调色'),
 ('表格','表头/内容分隔线',['voEls8l2RIhT3k4tQk1V6','1vXkt5jIielgtR4ipvzy8'],'admin-table / table-scroll','规范色板表头/奇偶行/选中态；固定列叠加背景防透出'),
 ('卡片','业务画板补充',['gikbC3t8uxeoq7IyvXlGB','1Q6Q1uJi3mAamRMsUqtGu'],'panel / card','rgba(80,177,249,.12)，12px圆角；不作为控件通用圆角'),
]
with zipfile.ZipFile(source.SOURCE) as z:
    doc=json.loads(z.read('document.json'));page=json.loads(z.read(doc['pages'][0]['_ref']+'.json'))
lookup={n['do_objectID']:(n,p) for n,p,v in source.walk(page) if v}
records=[]
for category,state,ids,target,decision in rules:
    layers=[]
    for layer_id in ids:
        n,p=lookup[layer_id]
        layers.append({'id':layer_id,'path':p,'frame':n['frame'],'opacity':n.get('style',{}).get('contextSettings',{}).get('opacity',1),'fills':source.paint(n,'fills'),'borders':source.paint(n,'borders'),'radii':sorted(set(x.get('cornerRadius',0) for x in n.get('points',[]))),'shadows':n.get('style',{}).get('shadows',[])})
    records.append({'component':category,'states':state,'implementation':target,'decision':decision,'sourceLayers':layers})
(OUT/'component-mapping.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
lines=['# 组件与 Sketch 图层对照','','生产采用的参数以具体组件示例优先；全部可见原始测量另见 `evidence/`。业务容器尺寸沿用现有页面布局。','','|组件|状态|实现|采用规格|原稿图层 ID|','|---|---|---|---|---|']
for r in records:
    lines.append('|'+ '|'.join([r['component'],r['states'],r['implementation'],r['decision'],' / '.join(x['id'] for x in r['sourceLayers'])])+'|')
lines+=['','数据接口：`modelValue` / `update:modelValue` / `change`；选择器同时兼容现有原生 change 事件。日期字符串保持本地 `YYYY-MM-DD` / `YYYY-MM-DDTHH:mm[:ss]`，不调用 UTC 转换。','','状态核对：颜色及 alpha、背景、边框、圆角、字重、字号、行高、尺寸见 JSON；图层继承可见性由抽取器过滤。说明文字只作为来源上下文，不作为产品文案或样式值。']
(OUT/'component-mapping.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(f'{len(records)} component mappings; {len(aliases)} icon mappings')
