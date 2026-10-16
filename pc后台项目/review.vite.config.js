// Dedicated, loopback-only UI verification server. Never used by production builds.
import base from './vite.config.js'
import { fileURLToPath, URL } from 'node:url'
export default {
  ...base,
  plugins: [...base.plugins, {
    name: 'isolated-admin-review', enforce: 'pre',
    configResolved(config) { if (config.command !== 'serve') throw Error('UI review is development-only') },
    resolveId(id, importer) {
      if (id === './portalSync' && importer?.endsWith('/service.js')) return fileURLToPath(new URL('./review/portal.js', import.meta.url))
    },
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if (req.url.startsWith('/api/')) { res.statusCode = 503; res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ message: '隔离验收环境不连接真实业务服务' })); return }
        next()
      })
    },
    transformIndexHtml(html) { return html.replace('<title>', '<title>隔离样式验收 · ') },
  }],
  resolve: { ...base.resolve, alias: { ...base.resolve.alias, '@admin-provider': fileURLToPath(new URL('./review/provider.js', import.meta.url)) } },
  server: { ...base.server, host: '127.0.0.1', port: 5183, strictPort: true, proxy: {} },
}
