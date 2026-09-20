import axios from 'axios'
import { getToken } from './auth'

let unauthorizedHandler = () => {}
export const setUnauthorizedHandler = (handler) => { unauthorizedHandler = handler }

const request = axios.create({ baseURL: import.meta.env.VITE_APP_BASE_API, timeout: 10000 })

request.interceptors.request.use((config) => {
  config.sessionToken = config.skipAuth ? '' : getToken()
  if (config.sessionToken) config.headers.Authorization = `Bearer ${config.sessionToken}`
  return config
})

function rejectError(message, code, config, body) {
  const error = new Error(message)
  error.code = code
  error.errorCode = body?.errorCode
  error.requestId = body?.requestId
  if (code === 401 && !config?.skipUnauthorized) unauthorizedHandler(config?.sessionToken)
  return Promise.reject(error)
}

request.interceptors.response.use((response) => {
  const data = response.data
  // 若依业务接口以 code 判断结果，HTTP 200 不等于业务成功。
  if (!data || typeof data !== 'object' || typeof data.code !== 'number') {
    return rejectError('服务响应格式异常，请检查接口地址或联系管理员', 'INVALID_RESPONSE', response.config)
  }
  if (data.code === 200) return data
  return rejectError(data.msg || '请求未完成，请稍后重试', data.code, response.config, data)
}, (error) => {
  if (axios.isCancel(error)) return Promise.reject(error)
  const status = error.response?.status
  let message = error.response?.data?.msg
  if (status === 401) message = '登录状态已失效，请重新登录'
  else if (!message && error.code === 'ECONNABORTED') message = '请求超时，请检查后端服务后重试'
  else if (!message && (!status || status >= 500)) message = '暂时无法连接后端服务，请检查服务和代理配置后重试'
  else if (!message && status === 403) message = '当前账号无权执行此操作'
  return rejectError(message || `请求失败（${status || '网络异常'}）`, status || error.code, error.config, error.response?.data)
})

export default request
