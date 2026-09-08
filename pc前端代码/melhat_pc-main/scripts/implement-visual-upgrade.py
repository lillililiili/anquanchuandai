from pathlib import Path
import re
root = Path.cwd()
def edit(name, fn):
    p=root/name
    s=p.read_text(encoding='utf-8-sig')
    p.write_text(fn(s),encoding='utf-8')
# Runtime theme: one set of light tokens; retain independent semantic warning colors.
def theme(s):
    changes={'#f3f4f6':'#f4f7fa','#f7f8fa':'#f8fafc','#eef0f3':'#edf2f7','#f6f7f9':'#f4f7fb','#fff4e8':'#eaf2ff','#111827':'#172b45','#4b5563':'#52647a','#6b7280':'#6b7c90','#9ca3af':'#76869a','#e5e7eb':'#e2e8f0','#d1d5db':'#c8d5e4','#eceef1':'#ffffff','#e2e5ea':'#e2e8f0'}
    for a,b in changes.items(): s=s.replace(a,b)
    for key in ['border-focus','color-primary','brand-accent']:
        s=s.replace('--'+key+': #b45309','--'+key+': #1765d1')
    for key in ['color-primary-hover','brand-accent-hover']:
        s=s.replace('--'+key+': #9a3412','--'+key+': #1254b3')
    s=s.replace('--color-primary-soft: rgba(180, 83, 9, 0.12)','--color-primary-soft: rgba(23, 101, 209, 0.10)')
    s=s.replace('--sidebar-text-active: #172b45','--sidebar-text-active: #1765d1').replace('--sidebar-active: #ffffff','--sidebar-active: #eaf2ff')
    s=s.replace('--sidebar-hover: rgba(17, 24, 39, 0.05)','--sidebar-hover: #f4f7fb')
    s=s.replace('--radius-sm: 3px','--radius-sm: 6px').replace('--radius: 4px','--radius: 8px').replace('--radius-lg: 6px','--radius-lg: 12px').replace('--radius-xl: 8px','--radius-xl: 16px')
    s=s.replace("'IBM Plex Sans', 'Noto Sans SC', 'PingFang SC', 'Microsoft YaHei', sans-serif", "'Microsoft YaHei', 'PingFang SC', 'Segoe UI', sans-serif")
    s=s.replace("'IBM Plex Mono', 'SFMono-Regular', Consolas, monospace", "'SFMono-Regular', Consolas, monospace")
    s=s.replace('font-weight: 500;\n  line-height: var(--leading-normal)', 'font-weight: 400;\n  line-height: var(--leading-normal)')
    s=s.replace('--shadow-sm: 0 1px 2px rgba(17, 24, 39, 0.06)', '--shadow-sm: 0 3px 14px rgba(23, 43, 69, 0.035)')
    s=s.replace('rgba(180, 83, 9, 0.22)', 'rgba(23, 101, 209, 0.16)').replace('--shadow-glow: 0 8px 22px rgba(180, 83, 9, 0.14)', '--shadow-glow: 0 8px 22px rgba(23, 101, 209, 0.10)')
    s=s.replace('Cool gray shell, white surfaces, safety-amber accent, high-contrast type.', 'Porcelain white surfaces, cobalt and teal identity, clear operational data.')
    s=re.sub(r'\.stat-card::before,\n\.dashboard-card::before \{.*?\n\}', '', s, flags=re.S)
    s=re.sub(r'/\* Reusable data-page polish.*?(?=\.operation-buttons)', '', s, flags=re.S)
    s=s.replace('  --el-font-size-base: 14px;', '  --el-font-size-base: 14px;\n  --color-accent: #148b98;\n  --el-color-primary-light-9: #eef5ff;\n  --el-color-primary-light-8: #dceaff;\n  --el-color-primary-light-5: #8bb2e8;\n  --el-color-primary-dark-2: #1254b3;')
    s += '\n.stat-value, .stat-num, .el-table { font-variant-numeric: tabular-nums; }\n#app .app-main .app-container:has(> .module-header) { padding-top: 20px; }\n.el-button.is-link[aria-label] { min-width: 32px; }\n'
    return s
edit('src/assets/styles/index.scss',theme)
def vars(s):
    for a,b in {'#f3f4f6':'#f4f7fa','#111827':'#172b45','#4b5563':'#52647a','#e5e7eb':'#e2e8f0','#eceef1':'#ffffff'}.items(): s=s.replace(a,b)
    s=re.sub(r'(\$(?:brand-primary|brand-accent|border-focus|base-menu-active-indicator): )#b45309',r'\g<1>#1765d1',s)
    s=s.replace('$brand-primary-hover: #9a3412','$brand-primary-hover: #1254b3').replace('$brand-accent-hover: #9a3412','$brand-accent-hover: #1254b3')
    s=s.replace('$radius: 4px','$radius: 8px').replace('$radius-lg: 6px','$radius-lg: 12px').replace('$radius-xl: 8px','$radius-xl: 16px')
    return s
edit('src/assets/styles/variables.module.scss',vars)
edit('src/assets/styles/element/_vars.scss',lambda s:s.replace('$--color-primary: #b45309','$--color-primary: #1765d1'))
edit('src/store/modules/settings.js',lambda s:s.replace("theme: '#b45309'","theme: '#1765d1'"))
edit('src/assets/styles/sidebar.scss',lambda s:s.replace('border-radius: 4px','border-radius: 8px').replace('box-shadow: var(--shadow-sm);','box-shadow: none;'))
edit('src/main.js',lambda s:s.replace("import App from './App'", "import BrandLogo from '@/components/BrandLogo/index.vue'\nimport ModuleHeader from '@/components/ModuleHeader/index.vue'\nimport BrandedEmpty from '@/components/BrandedEmpty/index.vue'\nimport App from './App'").replace("app.component('DictTag', DictTag)","app.component('BrandLogo', BrandLogo)\napp.component('ModuleHeader', ModuleHeader)\napp.component('BrandedEmpty', BrandedEmpty)\napp.component('DictTag', DictTag)"))
# Each page owns its header so viewport-based maps and monitor grids can reserve its space.
modules=['group','live','hat','fence','track','intercom','tts','sos','file']
for name in modules:
    path=f'src/views/{name}/index.vue'
    compact=' compact' if name in ['live','track'] else ''
    edit(path,lambda s,n=name,c=compact:s.replace('<div class="app-container">',f'<div class="app-container">\n    <ModuleHeader{c} module="{n}" />',1))
for p in (root/'src/views/system').rglob('*.vue'):
    s=p.read_text(encoding='utf-8-sig')
    if '<div class="app-container">' in s:
        s=s.replace('<div class="app-container">','<div class="app-container">\n    <ModuleHeader module="system" :title="$route.meta.title || \'系统管理\'" />',1)
        p.write_text(s,encoding='utf-8')
# Real table content remains unchanged; empty slots provide a reusable branded fallback.
for folder in [root/'src/views'/n for n in modules]+[root/'src/views/system']:
    for p in folder.rglob('*.vue'):
        s=p.read_text(encoding='utf-8-sig')
        if '#empty' not in s:
            s=re.sub(r'(<el-table(?=[\s>])(?:[^>"\']|"[^"]*"|\'[^\']*\')*>)',r'\1\n      <template #empty><BrandedEmpty compact description="暂无记录" /></template>',s)
        s=re.sub(r'<el-empty([^>]*?)/>',r'<BrandedEmpty\1/>',s)
        p.write_text(s,encoding='utf-8')
edit('src/views/track/index.vue',lambda s:s.replace('  height: calc(100vh - 60px);\n  overflow: hidden;', '  height: calc(100vh - 60px);\n  overflow: hidden;\n  display: flex;\n  flex-direction: column;').replace('.sidebar-layout {\n  height: 100%;','.sidebar-layout {\n  flex: 1;\n  min-height: 0;').replace('border-radius: 4px;', 'border-radius: var(--radius-lg);'))
edit('src/views/hat/index.vue',lambda s:s.replace('<div class="stat-card">','<div class="stat-card">\n          <img class="stat-art" alt="" aria-hidden="true" src="/visuals/hat.webp" />').replace('min-height: 100vh;','min-height: 100%;').replace('<el-col :span="8">','<el-col :md="8" :sm="8" :xs="24">').replace('</style>', '''
.stat-card { overflow: hidden; min-height: 112px; }
.stat-art { position: absolute; right: 0; top: 0; width: 45%; height: 100%; object-fit: cover; opacity: .45; pointer-events: none; mask-image: linear-gradient(to right, transparent, #000 65%); }
.stat-content, .stat-icon-wrapper { position: relative; z-index: 1; }
.stat-content .stat-value { font-size: 30px; }
@media(max-width:767px) { .stat-card { margin-bottom: 12px; } }
</style>''',1))
edit('src/views/file/index.vue',lambda s:s.replace('border-radius: 4px;', 'border-radius: var(--radius);'))
# New unified sidebar identity.
p=root/'src/layout/components/Sidebar/Logo.vue'
p.write_text('''<template>
  <div class="sidebar-logo-container">
    <router-link class="sidebar-logo-link" to="/" aria-label="分体式智能安全帽平台首页">
      <BrandLogo :caption="!collapse" :compact="collapse" />
    </router-link>
  </div>
</template>
<script setup>
defineProps({ collapse: { type: Boolean, required: true } })
</script>
<style scoped>
.sidebar-logo-container { display: flex; align-items: center; justify-content: center; height: 60px; border-bottom: 1px solid var(--sidebar-border); background: var(--sidebar-bg); }
.sidebar-logo-link { display: flex; align-items: center; justify-content: center; height: 60px; width: 100%; padding: 0 12px; }
.sidebar-logo-link :deep(.brand-logo) { gap: 8px; }
.sidebar-logo-link :deep(.brand-logo__name) { font-size: 12px; }
.sidebar-logo-link :deep(.brand-logo img) { width: 32px; height: 36px; }
</style>
''',encoding='utf-8')
def html(s):
    s=re.sub(r'    <link rel="preconnect".*?    <title>', '    <title>',s,flags=re.S)
    s=s.replace('initial-scale=1, maximum-scale=1, user-scalable=no','initial-scale=1')
    s=s.replace('/favicon.ico','/favicon.ico?v=20260906').replace('/favicon.png','/favicon.png?v=20260906')
    s=s.replace('#b45309','#1765d1').replace('#2a2e29','#f4f7fa').replace('color: #fff;','color: #172b45;')
    s=s.replace('<html>','<html lang="zh-CN">')
    return s
edit('index.html',html)
print('Applied shared theme, brand components, module headers and table empty states.')
