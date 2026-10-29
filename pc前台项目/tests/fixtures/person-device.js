// Fail closed if opened via the daily Vite server or a production build.
if (!import.meta.env.DEV || location.hostname !== '127.0.0.1' || location.port !== '5194') {
  document.getElementById('app').textContent = '此夹具仅允许在独立的 127.0.0.1:5194 验收服务运行。';
  throw Error('Isolated fixture origin required');
}
const { createApp } = await import('vue');
const { installUiSpec } = await import('@ui-spec/install');
const { createRouter, createWebHashHistory } = await import('vue-router');
const { default: Fixture } = await import('./PersonDeviceFixture.vue');
const { closeModal } = await import('../../src/stores/modal.js');
await import('../../src/styles/index.css');
await import('@ui-spec/tokens.css');
await import('../../src/styles/spec-theme.css');
await import('../../src/styles/spec-screen.css');
await import('../../src/styles/spec-adapter.css');
await import('@ui-spec/controls.css');
await import('@ui-spec/icon-masks.css');
await import('../../src/styles/portal-shell.css');
await import('../../src/styles/portal-business.css');
await import('@ui-spec/dialog.css');
const files = import.meta.glob('../../src/views/*/*View.vue');
const definitions = [ ['overview','/overview'], ['personnel','/personnel'], ['person','/person/:id'], ['works','/works'], ['work','/work/:id'], ['video','/video'], ['single','/single/:id'], ['materials','/materials'], ['location','/location'], ['tracks','/tracks/:id?'], ['fences','/fences'], ['alarms','/alarms'], ['event','/event/:id'], ['dispatch','/dispatch'], ['sos','/sos'], ['statistics','/statistics'], ['screen','/screen'] ];
const router = createRouter({ history: createWebHashHistory(), routes: [
  { path: '/', redirect: '/personnel' },
  ...definitions.map(([name,path]) => ({ name, path, component: files[`../../src/views/${name}/${name[0].toUpperCase() + name.slice(1)}View.vue`] })),
  { path: '/:pathMatch(.*)*', redirect: '/personnel' },
] });
router.afterEach(() => closeModal());
const app = createApp(Fixture); installUiSpec(app); app.use(router); await router.isReady(); app.mount('#app');
