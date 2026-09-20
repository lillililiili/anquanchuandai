// Only installed by the admin-mock build. The original HTML remains unchanged.
export function transformAdminHtml(html) {
  return html
    .replace(/<script\b[^>]*src=["']https?:\/\/[^"']+["'][^>]*>\s*<\/script>/gi, '')
    .replace(/<link\b[^>]*(?:icon)[^>]*>/gi, '')
    .replace('/src/main.js', '/src/admin-mock/main.js')
    .replace('<title>分体式智能安全帽平台</title>', '<title>智能穿戴设备平台 · 管理中心</title><link rel="icon" href="data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 32 32%22%3E%3Crect width=%2232%22 height=%2232%22 rx=%228%22 fill=%22%231765d1%22/%3E%3Ctext x=%225%22 y=%2224%22 fill=%22white%22 font-size=%2224%22%3EW%3C/text%3E%3C/svg%3E">')
}

export function adminMockHtml() {
  return { name: 'admin-mock-html', transformIndexHtml: { order: 'pre', handler: transformAdminHtml } }
}
