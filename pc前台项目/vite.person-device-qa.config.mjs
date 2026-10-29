import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('.', import.meta.url));
const fixture = name => path.join(root, 'tests/fixtures', name);
const replacements = new Map([
  ['mock/runtime', fixture('person-device-runtime.js')],
  ['stores/session', fixture('person-device-session.js')],
  ['lib/auth', fixture('person-device-auth.js')],
]);
export default defineConfig({
  root, cacheDir: path.join(root, 'node_modules/.vite-person-device-qa'), envDir: fixture('.no-environment'),
  plugins: [{
    name: 'isolated-person-device-qa', enforce: 'pre',
    resolveId(id, importer) {
      let relative;
      if (id.startsWith('@/')) relative = id.slice(2);
      else if (id.startsWith('.') && importer) relative = path.relative(path.join(root,'src'), path.resolve(path.dirname(importer.split('?')[0]), id)).replaceAll('\\','/');
      else if (path.isAbsolute(id)) relative = path.relative(path.join(root,'src'), id).replaceAll('\\','/');
      return replacements.get(relative?.replace(/\.js$/, ''));
    },
    configureServer(server) {
      server.middlewares.use((request, response, next) => {
        response.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' ws://127.0.0.1:5194; media-src 'none'; worker-src 'self' blob:; object-src 'none'; frame-src 'none'");
        if (/^\/api(?:\/|\?|$)/.test(request.url || '')) {
          response.statusCode = 503; response.setHeader('Content-Type', 'application/json');
          response.end(JSON.stringify({ message: 'Isolated browser fixture: backend requests are disabled' })); return;
        }
        next();
      });
    },
  }, vue()],
  resolve: { dedupe: ['vue'], alias: { '@ui-spec': path.resolve(root,'../shared/ui-spec'), '@': path.join(root,'src') } },
  optimizeDeps: { entries: [fixture('person-device.html')], include: [
    'vue', 'vue-router', 'hls.js', 'agora-rtc-sdk-ng', 'sip.js',
    'ol/Map', 'ol/View', 'ol/layer/Tile', 'ol/source/XYZ', 'ol/layer/Vector', 'ol/source/Vector',
    'ol/Feature', 'ol/geom/Point', 'ol/geom/LineString', 'ol/geom/Polygon', 'ol/Overlay',
    'ol/interaction/DragPan', 'ol/interaction/defaults', 'ol/proj', 'ol/extent', 'ol/style',
  ] },
  server: { host: '127.0.0.1', port: 5194, strictPort: true, fs: { allow: [path.resolve(root,'..')] }, proxy: {} },
  // This configuration is for a local test server only; normal builds do not include the fixture.
});
