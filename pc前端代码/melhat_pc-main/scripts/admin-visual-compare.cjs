// Evidence composition only. Pass a locally available sharp module and selected concept PNG.
const sharp = require(process.argv[2])
const path = require('node:path')
async function main() {
  const folder = path.resolve('output/playwright/admin-visual')
  const reference = await sharp(process.argv[3]).resize(800, 1120, { fit: 'contain', background: '#eef3fa' }).png().toBuffer()
  const login = await sharp(path.join(folder, 'login-1440.png')).resize(800, 560, { fit: 'contain', background: '#eef3fa' }).png().toBuffer()
  const overview = await sharp(path.join(folder, 'overview-1440.png')).resize(800, 560, { fit: 'contain', background: '#eef3fa' }).png().toBuffer()
  await sharp({ create: { width: 1600, height: 1120, channels: 3, background: '#eef3fa' } }).composite([{ input: reference, left: 0, top: 0 }, { input: login, left: 800, top: 0 }, { input: overview, left: 800, top: 560 }]).png().toFile(path.join(folder, 'reference-vs-implementation.png'))
}
main().catch(e => { console.error(e); process.exitCode = 1 })
