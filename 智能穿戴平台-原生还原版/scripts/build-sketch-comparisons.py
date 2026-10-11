"""Build this revision's comparison gallery from actual browser captures."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
out = root / 'qa' / 'sketch'
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 21)
for name in ('overview', 'personnel', 'person-P1', 'fences', 'screen'):
    pair = [Image.open(out / stage / (name + '.png')).convert('RGB') for stage in ('before', 'after')]
    widths = 960
    images = [im.resize((widths, round(im.height * widths / im.width))) for im in pair]
    sheet = Image.new('RGB', (widths * 2, max(im.height for im in images) + 52), '#121e37')
    draw = ImageDraw.Draw(sheet)
    for i, (im, label) in enumerate(zip(images, ('上一版 · 修正前', 'Sketch 核实后 · 当前版本'))):
        sheet.paste(im, (i * widths, 52))
        draw.text((i * widths + 18, 13), label, font=font, fill='#d1dae5')
    sheet.save(out / ('comparison-' + name + '.png'))

page = (root / 'qa' / 'theme' / 'index.html').read_text('utf-8')
page = page.replace('UI 规范样式改造 · 前后对比', 'Sketch 参数校正 · 前后对比')
page = page.replace('智能穿戴平台 · 样式前后对比', '智能穿戴平台 · Sketch 参数校正')
page = page.replace('统一深蓝主题、字体层级、边框与组件状态，保留现有导航、分栏、模块与交互流程。', '左侧为上一版，右侧为按 Sketch 原始参数校正后的版本。保留现有导航、分栏、模块与交互流程。')
page = page.replace('<i style="background:#17294a"></i>面板 #17294A', '<i style="background:rgba(80,177,249,.12)"></i>卡片 #50B1F9 · 12%')
page = page.replace('<a href="acceptance.md">验收记录</a>', '<a href="acceptance.md">验收记录</a>　 ·　 <a href="../../STYLE.md">项目样式约定</a>　 ·　 <a href="reference/comparison.html">修正依据</a>')
page = page.replace('修改前<a id="before-link"', '上一版<a id="before-link"')
page = page.replace('修改后<a id="after-link"', 'Sketch 核实后<a id="after-link"')
(out / 'index.html').write_text(page, encoding='utf-8')
print('Wrote 5 image comparisons and the 18-page gallery:', out)
