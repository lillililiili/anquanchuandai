import baseConfig from '../../vite.config.js'
import path from 'node:path'
export default async (env) => {
  const config = await baseConfig(env)
  const baseline = path.resolve('backups/visual-upgrade-20260906-143125')
  return { ...config, root: baseline, cacheDir: path.resolve('output/visual-upgrade/baseline-cache'), resolve: {...config.resolve, alias: {'@': path.join(baseline,'src')}}, server: {...config.server, host: '127.0.0.1', port:5176, strictPort:true} }
}
