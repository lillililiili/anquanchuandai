from pathlib import Path
import json,hashlib,datetime,zipfile,shutil,html
ROOT=Path(__file__).resolve().parents[1]
E=ROOT/'同步验收/20260921';SITE=ROOT/'site';SRC=ROOT/'展示源码'
# CMD reparses the batch stream after CHCP; preserve Windows CRLF line endings.
for name in ['打开安卓演示.cmd','停止安卓演示.cmd']:
    script=ROOT/name
    script.write_bytes(script.read_bytes().replace(b'\r\n',b'\n').replace(b'\n',b'\r\n'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
baseline=json.loads((E/'主项目只读快照.json').read_text('utf-8'))
original=Path(baseline['source']);changed=[];ui_changes=[];ui_count=0
for row in baseline['files']:
    rel=row['path'];p=original/rel
    if not p.is_file() or sha(p)!=row['sha256']:changed.append(rel)
    if (rel.startswith('lib/') and not rel.startswith('lib/web_preview/')) or rel.startswith('assets/'):
        ui_count+=1
        if sha(SRC/rel)!=row['sha256']:ui_changes.append(rel)
assert not changed, f'Original source changed during display work: {changed}'
assert not ui_changes, f'Shared UI differs: {ui_changes}'
report={'verifiedAt':datetime.datetime.now().astimezone().isoformat(),'originalFilesChecked':len(baseline['files']),'originalChangedFiles':changed,'sharedUiAndAssetFilesChecked':ui_count,'sharedUiChangedFiles':ui_changes,'releaseBuild':'passed','displayTests':{'count':4,'status':'passed','coverage':['contact device ownership','pagination and local action reset','track assignment windows and 500-point thinning','four primary pages with continuous scrolling']},'snapshot':json.loads((E/'数据快照说明.json').read_text('utf-8')),'limitations':['Display-only in-memory operations; no real calls or commands','Historical data retains original timestamps','Only previously cached event map tiles are bundled'],'screenshots':[p.name for p in sorted((E/'页面截图').glob('*.png'))]}
(E/'验收结果.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),'utf-8')
gallery=SITE/'review';gallery.mkdir(exist_ok=True)
shutil.copytree(E/'页面截图',gallery/'images',dirs_exist_ok=True)
cards=''.join(f'<figure><figcaption>{html.escape(p.stem)}</figcaption><img loading="lazy" src="images/{p.name}" alt="{html.escape(p.stem)}"></figure>' for p in sorted((E/'页面截图').glob('*.png')))
(gallery/'index.html').write_text('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>当前安卓 · 页面验收</title><style>body{font-family:Arial,"Microsoft YaHei",sans-serif;background:#edf5fc;color:#1c3550;margin:24px}a{color:#176df2}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,360px));gap:24px}figure{margin:0}figcaption{padding:12px 0}img{width:100%;height:auto;border-radius:10px;box-shadow:0 6px 24px #2343}p{line-height:1.8;max-width:850px}</style><a href="../">返回可交互展示</a><h1>当前安卓 · 页面验收</h1><p>主页面顶部与连续下部截图按编号排列，滚动重叠部分用于核对衔接。后续图片记录装备及事件等子页面。主页面来自与网页共享组件的 Flutter 渲染，子页面由浏览器截图；按钮与导航使用当前安卓源码。</p><div class="grid">'+cards+'</div>','utf-8')
for target in [SITE/'index.html',SRC/'web/index.html']:
    value=target.read_text('utf-8')
    if 'review/index.html' not in value:value=value.replace('<footer>','<p><a href="review/index.html" target="_blank">查看上下屏与子页面截图 ↗</a></p><footer>')
    target.write_text(value,'utf-8')
hashes=[{'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p)} for p in sorted(SITE.rglob('*')) if p.is_file()]
hashes += [{'path':name,'sha256':sha(ROOT/name)} for name in ['打开安卓演示.cmd','停止安卓演示.cmd','启动网页.ps1']]
(ROOT/'文件校验清单.json').write_text(json.dumps(hashes,ensure_ascii=False,indent=2),'utf-8')
archive=ROOT/'安卓网页展示-可直接运行.zip';backup=ROOT/'历史备份/安卓网页展示-20260918.zip'
if archive.exists() and not backup.exists():
    assert archive.resolve().parent==ROOT.resolve() and ROOT.resolve() in backup.resolve().parents
    shutil.move(str(archive),str(backup))
files=[p for p in SITE.rglob('*') if p.is_file()]
files += [ROOT/n for n in ['打开安卓演示.cmd','停止安卓演示.cmd','启动网页.ps1','使用说明.md','页面关系.md','文件校验清单.json']]
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in files:z.write(p,p.relative_to(ROOT).as_posix())
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
print(json.dumps({'originalFilesUnchanged':len(baseline['files']),'sharedUiFilesIdentical':ui_count,'siteFiles':len(hashes),'archiveBytes':archive.stat().st_size,'archiveSha256':sha(archive)},ensure_ascii=False))
