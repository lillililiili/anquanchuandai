from pathlib import Path
import re
root=Path.cwd()
# Correct header-adjacent search surfaces, and keep filters consistent on system pages.
for p in (root/'src/views/system').rglob('*.vue'):
    s=p.read_text(encoding='utf-8')
    def form(m):
        tag=m.group(0)
        return tag if 'class=' in tag or 'showSearch' not in tag else tag.replace('<el-form','<el-form class="search-form"',1)
    s=re.sub(r'<el-form(?=\s)[^>]*>',form,s)
    p.write_text(s,encoding='utf-8')
p=root/'src/views/login.vue'
s=p.read_text(encoding='utf-8').replace("65% center / cover", "right center / cover")
p.write_text(s,encoding='utf-8')
p=root/'src/components/Hamburger/index.vue'
s=p.read_text(encoding='utf-8').replace('<div style="padding: 0 15px" @click="toggleClick">','<button class="sidebar-toggle" :aria-expanded="isActive" :aria-label="isActive ? \'收起侧栏\' : \'展开侧栏\'" type="button" @click="toggleClick">').replace('  </div>','  </button>',1).replace('      height="64"','      aria-hidden="true"\n      height="20"').replace('      width="64"','      width="20"').replace('<style scoped>','<style scoped>\n.sidebar-toggle { display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0; min-width: 36px; height: 36px; padding: 0; border: 0; color: var(--text-secondary); background: transparent; cursor: pointer; }')
p.write_text(s,encoding='utf-8')
# Tooltip text also labels icon-only buttons for keyboard/screen-reader users.
for p in (root/'src/views').rglob('*.vue'):
    if p.parts[-2] not in ['hat','group','fence','intercom','tts','sos','file','track','live']: continue
    s=p.read_text(encoding='utf-8')
    s=re.sub(r'(<el-tooltip\s+content="([^"]+)"[^>]*>\s*<el-button)(?![^>]*aria-label)',lambda m:m[1]+' aria-label="'+m[2]+'"',s)
    p.write_text(s,encoding='utf-8')
print('Refined responsive artwork, filter cards and keyboard-accessible navigation.')
