import { describe, expect, it } from 'vitest'
import errorCode from '@/utils/errorCode'

describe('errorCode', () => {
  it('maps 401 403 409 to contract messages', () => {
    expect(errorCode['401']).toBe('未登录或登录已过期，请重新登录')
    expect(errorCode['403']).toBe('没有权限执行该操作')
    expect(errorCode['409']).toBe('当前状态冲突，请刷新后重试')
  })
})
