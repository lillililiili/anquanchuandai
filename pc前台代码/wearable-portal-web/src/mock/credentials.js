import { failure } from './errors.js'

// Local-only credential fixtures, never server authentication or production secrets.
// Imported exclusively by the build-time local transport.
const accounts = [
  { username: 'admin', password: 'Admin@2026', role: 'owner' },
  { username: 'verifier', password: 'Verify@2026', role: 'verifier' },
  { username: 'viewer', password: 'View@2026', role: 'reader' }
]

export function authenticate(credentials) {
  const username = typeof credentials?.username === 'string' ? credentials.username.trim() : ''
  const account = accounts.find(item => item.username === username && item.password === credentials?.password)
  if (!account) throw failure(401, '账号或密码错误', 'INVALID_CREDENTIALS')
  return account.role
}
