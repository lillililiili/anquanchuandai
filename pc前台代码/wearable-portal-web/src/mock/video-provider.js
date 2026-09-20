import clip from './assets/synthetic-monitor.webm?url'
import request from './request.js'
export const mockMediaProvider = {
  async acquire(context, signal) {
    await request.get('/mock-video/access', { params: context, signal })
    return { state: 'AVAILABLE', type: 'native', url: clip, sourceTime: null, release() {} }
  }
}
