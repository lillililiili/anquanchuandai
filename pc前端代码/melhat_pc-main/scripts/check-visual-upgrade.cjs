const fs = require('node:fs')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

const root = process.cwd()
const backup = path.join(root, 'backups/visual-upgrade-20260906-143125')
const output = path.join(root, 'output/visual-upgrade')
const changed = []
function walk(folder) {
  for (const entry of fs.readdirSync(folder, { withFileTypes: true })) {
    const file = path.join(folder, entry.name)
    if (entry.isDirectory()) walk(file)
    else {
      const relative = path.relative(root, file)
      const original = path.join(backup, relative)
      if (!fs.existsSync(original) || !fs.readFileSync(file).equals(fs.readFileSync(original))) changed.push(relative.replaceAll('\\', '/'))
    }
  }
}
walk(path.join(root, 'src'))
fs.writeFileSync(path.join(output, 'changed-source-files.json'), JSON.stringify(changed, null, 2))
const files = changed.filter(file => /\.(vue|js)$/.test(file))
const result = spawnSync(process.execPath, [path.join(root, 'node_modules/eslint/bin/eslint.js'), '--no-ignore', '--no-eslintrc', '--config', path.join(output, 'eslint-visual.cjs'), ...files, '--format', 'json', '--output-file', path.join(output, 'lint-visual.json')], { cwd: root, encoding: 'utf8' })
if (result.stdout) process.stdout.write(result.stdout)
if (result.stderr) process.stderr.write(result.stderr)
const lint = JSON.parse(fs.readFileSync(path.join(output, 'lint-visual.json'), 'utf8'))
const summary = { sourceFilesChanged: changed.length, filesChecked: lint.length, errors: lint.reduce((sum, file) => sum + file.errorCount, 0), warnings: lint.reduce((sum, file) => sum + file.warningCount, 0), check: 'Vue 3 essential rules and JavaScript/Vue parsing; SCSS checked by Vite production build.' }
fs.writeFileSync(path.join(output, 'static-check-summary.json'), JSON.stringify(summary, null, 2))
console.log(summary)
process.exit(result.status ?? 1)
