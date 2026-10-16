import base from './vite.config.js'
import { fileURLToPath, URL } from 'node:url'

// Local UI verification only: production uses vite.config.js and the real runtime.
export default {
  ...base,
  cacheDir: 'node_modules/.vite-modal-review',
  optimizeDeps: { entries: ['tests/fixtures/modal.html', 'portal-spec.html'] },
  plugins: [...base.plugins, {
    name: 'isolated-modal-review',
    configResolved(config) { if (config.command !== 'serve') throw Error('Review is development-only') },
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if (req.url.startsWith('/api/')) { res.statusCode = 503; res.end('Isolated UI review'); return }
        next()
      })
    },
  }],
  resolve: { ...base.resolve, alias: {
    '@/mock/runtime': fileURLToPath(new URL('./tests/fixtures/modal-runtime.js', import.meta.url)),
    ...base.resolve.alias,
  } },
  server: { ...base.server, host: '127.0.0.1', port: 5193, strictPort: true, proxy: {} },
}
