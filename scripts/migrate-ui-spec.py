"""Initial UI-only migration. Run once; source business models are not touched."""
from pathlib import Path
import json, re, urllib.parse

ROOT=Path(__file__).resolve().parents[1]
shared=ROOT/'shared/ui-spec'
old=ROOT/'智能穿戴平台-原生还原版/css'
tokens=(old/'theme-tokens.css').read_text('utf-8')
tokens=tokens.replace('"Source Han Sans CN", "思源黑体", "PingFang SC", "Microsoft YaHei", sans-serif','Arial, "UI Source Han", sans-serif').replace('Arial, "Source Han Sans CN", "PingFang SC", "Microsoft YaHei", sans-serif','Arial, "UI Source Han", sans-serif').replace('--theme-font-weight-title: 600','--theme-font-weight-title: 700')
tokens=tokens.replace('/* Existing Canvas consumers append hex alpha suffixes: keep these colors hex. */','/* Compatibility aliases for existing component styles. */')
(shared/'tokens.css').write_text(tokens,'utf-8')
icons=json.loads((shared/'icons.json').read_text('utf-8'))
masks=[]
for name in ['check','minus']:
 i=icons[name]; svg=f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{i["viewBox"]}">{i["body"]}</svg>'
 masks.append(f'--ui-{name}-icon:url("data:image/svg+xml,{urllib.parse.quote(svg)}");')
(shared/'icon-masks.css').write_text(':root { '+''.join(masks)+' }\n','utf-8')
# Verified previous extraction is a starting point; new controls override native selectors below.
(ROOT/'pc前台项目/src/styles/spec-theme.css').write_text((old/'theme.css').read_text('utf-8'),'utf-8')
(ROOT/'pc前台项目/src/styles/spec-screen.css').write_text((old/'theme-screen.css').read_text('utf-8'),'utf-8')
for app in ['pc前台项目','pc后台项目']:
 path=ROOT/app/'vite.config.js';s=path.read_text('utf-8')
 s=s.replace('resolve: {','resolve: {\n    dedupe: ["vue"],').replace('alias: {','alias: {\n      "@ui-spec": fileURLToPath(new URL("../shared/ui-spec", import.meta.url)),')
 s=s.replace('server: {','server: {\n    fs: { allow: [fileURLToPath(new URL("..", import.meta.url))] },')
 path.write_text(s,'utf-8')
 path=ROOT/app/('src/main.js' if app=='pc前台项目' else 'main.js');s=path.read_text('utf-8')
 s='import { installUiSpec } from "@ui-spec/install";\n'+s
 css='\nimport "@ui-spec/tokens.css";\n'
 css+= 'import "./styles/spec-theme.css";\nimport "./styles/spec-screen.css";\nimport "./styles/spec-adapter.css";\n' if app=='pc前台项目' else 'import "./styles/spec-adapter.css";\n'
 css+='import "@ui-spec/controls.css";\nimport "@ui-spec/icon-masks.css";\n'
 marker='import "./styles/index.css";' if app=='pc前台项目' else "import './styles.css'"
 s=s.replace(marker,marker+css)
 if app=='pc前台项目':s=s.replace('const app = createApp(App);','const app = createApp(App);\ninstallUiSpec(app);')
 else:s=s.replace('createApp(App).component','const app = createApp(App)\ninstallUiSpec(app)\napp.component')
 path.write_text(s,'utf-8')
 if app=='pc后台项目':
  for p in (ROOT/app).rglob('*.vue'):
   if 'node_modules' in p.parts:continue
   s=p.read_text('utf-8').replace("from '@element-plus/icons-vue'","from '@ui-spec/element-icons'")
   s=re.sub(r'<(/?)select\b',r'<\1UiSelect',s)
   s=re.sub(r'<input\b(?=[^>]*\btype=[\"\x27](?:date|datetime-local)[\"\x27])', '<UiDatePicker',s)
   p.write_text(s,'utf-8')
path=ROOT/'pc前台项目/src/components/ui/AppIcon.vue'
path.write_text('''<script setup>
import UiIcon from '@ui-spec/UiIcon.vue'
defineProps({name:{type:String,required:true},color:{type:String,default:''}})
</script>
<template><UiIcon :name="name" :class="color" /></template>
''','utf-8')
path=ROOT/'pc前台项目/src/components/ui/AppSelect.vue'
path.write_text('''<script setup>
import UiSelect from '@ui-spec/UiSelect.vue'
defineProps({modelValue:{type:[String,Number],default:''},options:{type:Array,default:()=>[]},name:{type:String,default:''},disabled:Boolean,ariaLabel:{type:String,default:''}})
defineEmits(['update:modelValue'])
</script>
<template><UiSelect :model-value="modelValue" :options="options" :name="name || undefined" :disabled="disabled" :aria-label="ariaLabel || undefined" @update:model-value="$emit('update:modelValue',$event)" /></template>
''','utf-8')
path=ROOT/'pc前台项目/src/components/ui/AppInput.vue';s=path.read_text('utf-8').replace('<script setup>','<script setup>\nimport UiDatePicker from "@ui-spec/UiDatePicker.vue";')
s=s.replace('<input\n','<UiDatePicker v-if="type === \'date\' || type === \'datetime-local\'" v-bind="$props" @update:model-value="$emit(\'update:modelValue\', $event)" />\n  <input v-else\n');path.write_text(s,'utf-8')
path=ROOT/'pc后台项目/components/RowMore.vue'
path.write_text('''<template><UiPopover><div class="row-more-content"><slot /></div></UiPopover></template>
<script setup>
import UiPopover from '@ui-spec/UiPopover.vue'
</script>
''','utf-8')
path=ROOT/'pc前台项目/src/components/domain/PlantMap.vue';s=path.read_text('utf-8');s='import-placeholder\n'+s if False else s
s=s.replace('<script setup>','<script setup>\nimport { iconMarkup } from "@ui-spec/icons";').replace("'<i class=\"ri-user-fill\" aria-hidden=\"true\"></i>'",'iconMarkup("user-fill")');path.write_text(s,'utf-8')
path=ROOT/'pc前台项目/src/views/screen/screen-runtime.js';s=path.read_text('utf-8');s='import { iconMarkup } from "@ui-spec/icons";\n'+s
start=s.index('const symbols = {');end=s.index('\n};',start)+3
s=s[:start]+'const symbols = Object.fromEntries(["factory","chain","battery","pin","document","antenna","warning","worker","heart","oxygen","temperature"].map(name => [name,iconMarkup(name)]));'+s[end:]
path.write_text(s,'utf-8')
path=ROOT/'pc前台项目/index.html';s=path.read_text('utf-8').replace('    <link rel="stylesheet" href="/assets/remixicon.css" />\n','');path.write_text(s,'utf-8')
print('Shared assets, aliases, control adapters and entrypoints migrated.')
