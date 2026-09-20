import request from '@/utils/request'

export const login = (data) => request.post('/login', data, { skipAuth: true, skipUnauthorized: true })
export const getCaptcha = () => request.get('/captchaImage', { skipAuth: true, skipUnauthorized: true })
// 初始化失败由路由守卫或登录表单处理，避免与全局失效处理重复提示。
export const getInfo = () => request.get('/getInfo', { skipUnauthorized: true })
export const logout = () => request.post('/logout', null, { skipUnauthorized: true })
