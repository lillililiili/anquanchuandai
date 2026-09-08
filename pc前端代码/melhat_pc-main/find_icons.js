import fs from 'fs'
import path from 'path'

const collections = ['ri', 'lucide', 'mdi', 'mingcute']
const searchTerms = ['helmet', 'hat']

collections.forEach(prefix => {
  const dataPath = `./node_modules/@iconify-json/${prefix}/icons.json`
  if (fs.existsSync(dataPath)) {
    const data = JSON.parse(fs.readFileSync(dataPath, 'utf8'))
    const matches = Object.keys(data.icons).filter(name => 
      searchTerms.some(term => name.toLowerCase().includes(term))
    )
    console.log(`Collection [${prefix}]:`)
    matches.forEach(m => console.log(`  - ${prefix}:${m}`))
  }
})
