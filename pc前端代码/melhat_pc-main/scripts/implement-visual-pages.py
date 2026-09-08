from pathlib import Path
import re
root=Path.cwd()
p=root/'src/views/login.vue'
s=p.read_text(encoding='utf-8')
s=re.sub(r'<div class="brand-lockup">.*?</div>', '<div class="brand-lockup"><BrandLogo caption /></div>', s, count=1, flags=re.S)
s=re.sub(r'<div class="mobile-brand">.*?</div>', '<div class="mobile-brand"><BrandLogo caption /></div>', s, count=1, flags=re.S)
s=s.replace('<p class="visual-kicker">FIELD DISPATCH</p>', '<p class="visual-kicker">智能感知 · 安全协同</p>')
s=s.replace('矿区作业调度台<br />安全帽在线值守','每一份专注<br /><span>都有安全守护</span>')
s=s.replace('集中掌握设备、人员、告警与现场音视频，帮助值班人员快速判断并稳妥响应。','连接设备、人员与现场，让每一次作业清晰可见，<br />让每一次响应及时抵达。')
s=s.replace('<span>实时状态</span>','<span><svg-icon icon-class="helmet" /> 设备感知</span>').replace('<span>应急响应</span>','<span><svg-icon icon-class="sos" /> 安全预警</span>').replace('<span>协同调度</span>','<span><svg-icon icon-class="walkie-talkie" /> 协同调度</span>')
s=s.replace('<p class="login-eyebrow">分体式智能安全帽平台</p>','<p class="login-eyebrow">安全运营工作台</p>').replace('<h2>进入调度台</h2>','<h2>欢迎回来</h2>').replace('使用值班账号登录，查看设备、人员与告警。','登录您的账号，开始安全有序的一天。')
s=s.replace("import appLogo from '@/assets/logo/app-logo.png'\n",'')
s=s[:s.index('<style lang="scss" scoped>')]+'''<style lang="scss" scoped>
.login-page { display: grid; grid-template-columns: minmax(0, 58%) minmax(420px, 42%); height: 100dvh; min-height: 620px; background: #f4f7fa; overflow-y: auto; }
.login-visual { position: relative; min-height: 100%; overflow: hidden; background: #eaf0f6 url('/visuals/login-hero.webp') 65% center / cover no-repeat; }
.visual-content { position: relative; display: flex; flex-direction: column; min-height: 100%; padding: 40px clamp(32px, 4.2vw, 80px); }
.brand-lockup { display: flex; align-items: center; }
.brand-lockup :deep(.brand-logo__name) { font-size: 17px; }
.brand-lockup :deep(.brand-logo img) { width: 44px; height: 48px; }
.visual-copy { margin-top: clamp(48px, 9vh, 108px); max-width: 580px; }
.visual-kicker { margin: 0 0 20px; color: #1765d1; font-size: 13px; letter-spacing: 4px; font-weight: 600; }
.visual-copy h1 { margin: 0; color: #172b45; font-size: clamp(34px, 3.3vw, 58px); font-weight: 600; line-height: 1.35; letter-spacing: 1px; }
.visual-copy h1 span { color: #1765d1; }
.visual-description { margin: 22px 0 0; color: #52647a; font-size: 14px; line-height: 1.9; }
.visual-meta { display: flex; flex-wrap: wrap; align-items: center; gap: 24px; margin-top: auto; padding-top: 50px; color: #253e57; font-size: 12px; }
.visual-meta span { display: flex; align-items: center; gap: 7px; padding: 10px 12px; border: 1px solid rgba(255,255,255,.8); border-radius: 8px; background: rgba(255,255,255,.85); }
.visual-meta .svg-icon { color: #1765d1; width: 16px; height: 16px; }
.login-panel { display: flex; align-items: center; justify-content: center; min-height: 100%; padding: 36px clamp(28px, 3.4vw, 64px); background: #f7f9fc; border-left: 1px solid #e2e8f0; }
.mobile-brand { display: none; }
.login-form { width: 100%; max-width: 440px; padding: 42px 36px 30px; border: 1px solid #e2e8f0; border-radius: 20px; background: #fff; box-shadow: 0 16px 50px rgba(23,43,69,.055); }
.login-header { margin-bottom: 36px; }
.login-eyebrow { margin: 0 0 14px; font-size: 12px; font-weight: 500; letter-spacing: 2px; color: #148b98; }
.login-header h2 { margin: 0; font-size: 30px; font-weight: 600; color: #172b45; line-height: 1.35; }
.login-header > p:last-child { margin: 12px 0 0; font-size: 13px; line-height: 1.7; color: #6b7c90; }
.field-label { display: block; width: 100%; margin-bottom: 9px; color: #334b65; font-size: 13px; font-weight: 500; }
.login-form :deep(.el-form-item) { display: block; margin-bottom: 23px; }
.login-form :deep(.el-form-item__content) { display: block; line-height: normal; }
.login-form :deep(.el-input__wrapper) { min-height: 48px; padding-inline: 14px; border-radius: 8px; background: #f8fafc; }
.input-icon { width: 16px; height: 16px; color: #76869a; }
.captcha-row { display: grid; grid-template-columns: minmax(0, 1fr) 110px; gap: 10px; }
.login-code { height: 48px; padding: 0; overflow: hidden; border: 1px solid #e2e8f0; border-radius: 8px; background: #fff; cursor: pointer; }
.login-code-img { display: block; width: 100%; height: 100%; object-fit: contain; }
.submit-item { margin-top: 30px; }
.login-button { width: 100%; min-height: 48px; border-radius: 8px; font-size: 15px; font-weight: 500; box-shadow: 0 6px 16px rgba(23,101,209,.16); }
.login-support { margin: 30px 0 0; color: #6b7c90; font-size: 11px; text-align: center; line-height: 1.7; }
@media (max-width: 1180px) { .visual-content { padding: 32px; } .visual-meta { gap: 8px; } .login-panel { padding: 28px; } .login-form { padding: 36px 28px 26px; } }
@media (max-width: 820px) { .login-page { display: block; min-height: 100dvh; height: auto; } .login-visual { display: none; } .login-panel { flex-direction: column; align-items: stretch; justify-content: center; gap: 36px; min-height: 100dvh; padding: 32px 22px; border: 0; } .mobile-brand { display: flex; justify-content: center; } .login-form { align-self: center; padding: 30px 24px 24px; border-radius: 16px; } .login-header { margin-bottom: 28px; } .login-header h2 { font-size: 28px; } }
</style>
'''
p.write_text(s,encoding='utf-8')
# Light wallboard palette, actual data and chart logic preserved.
p=root/'src/views/big-screen/index.vue'
s=p.read_text(encoding='utf-8')
s=s.replace('<svg-icon icon-class="helmet" class-name="header-logo-icon" />','<BrandLogo compact />').replace('分体式智能安全帽管理平台','分体式智能安全帽平台')
replacements={'#0c1118':'#f4f7fa','#131a23':'#ffffff','#18212b':'#f4f7fb','#101721':'#ffffff','#f1f5f9':'#172b45','#9eabb9':'#52647a','#74a7df':'#148b98','#4f8ff7':'#1765d1','#39b980':'#15845c','#d9a441':'#ad770d','#c9833e':'#b45309','#e06363':'#c43c43',"rgba(19,26,35,0.96)":"rgba(255,255,255,0.98)",'rgba(116,167,223,0.28)':'#e2e8f0','rgba(132, 151, 174, 0.22)':'#e2e8f0','rgba(93, 156, 236, 0.42)':'#c8d5e4','rgba(15, 30, 56, 0.6)':'#f5f8fc','rgba(15, 30, 56, 0.8)':'#edf3fa'}
for a,b in replacements.items(): s=s.replace(a,b)
s=s.replace('background: $screen-bg;',"background: $screen-bg url('/visuals/screen-bg.webp') center / cover no-repeat;")
s=s.replace('Fixed dark wallboard palette: restrained contrast, operational status first.','Light wallboard palette: shared brand and clear operational status.')
s=s.replace('border-radius: 4px;','border-radius: 8px;').replace('border-radius: 8px;\n  overflow: hidden;\n  position: relative;', 'border-radius: 12px;\n  box-shadow: 0 3px 14px rgba(23,43,69,.04);\n  overflow: hidden;\n  position: relative;')
s=s.replace('font-size: 11px;', 'font-size: 12px;').replace('letter-spacing: 3px;','letter-spacing: 1px;')
s=s.replace('color: lighten($accent-cyan, 20%);','color: darken($accent-cyan, 10%);')
s=s.replace('<header class="screen-header">','<header class="screen-header">\n      <router-link class="screen-back" to="/">‹ 返回工作台</router-link>')
s=s.replace('</style>', '''
.screen-back { position: absolute; left: 24px; color: var(--color-primary); font-size: 13px; padding: 8px 12px; border: 1px solid var(--border-color); border-radius: 8px; }
.header-content { align-items: center; gap: 12px; }
.alarm-info, .group-info, .single-info, .broadcast-info { min-width: 0; }
@media(max-width: 1000px) { .header-right { right: 12px; } .header-time { letter-spacing: 0; } .screen-back { left: 12px; } }
</style>''')
p.write_text(s,encoding='utf-8')
# Neutral empty video tiles; streams retain their own dark video surfaces.
p=root/'src/views/live/index.vue'
s=p.read_text(encoding='utf-8')
s=s.replace('<el-icon class="camera-icon"><VideoCamera /></el-icon>\n                <span class="placeholder-text">暂无视频流</span>','<BrandedEmpty compact description="暂无视频流" device />')
s=s.replace('<div class="video-placeholder video-placeholder-full" @click="handleAdd">\n            <el-icon class="camera-icon"><VideoCamera /></el-icon>\n            <span class="placeholder-text">点击添加监控</span>\n          </div>', '<button class="video-placeholder video-placeholder-full" type="button" @click="handleAdd">\n            <BrandedEmpty :compact="splitType > 4" description="点击添加监控" device />\n          </button>')
s=s.replace('</style>', '''
button.video-placeholder-full { width: 100%; border: 0; font: inherit; cursor: pointer; background: var(--bg-soft); }
button.video-placeholder-full:hover { background: var(--bg-selected); }
.monitor-header { flex-shrink: 0; margin-bottom: 8px; padding-top: 0; }
.monitor-grid-container { min-height: 0; }
.monitor-item { border-radius: 12px; }
.grid-16 .branded-empty :deep(img), .grid-25 .branded-empty :deep(img) { display: none; }
</style>''',1)
p.write_text(s,encoding='utf-8')
print('Login, wallboard and empty monitor tiles redesigned.')
