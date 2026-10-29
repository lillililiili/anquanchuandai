export const DIRECT_DEVICE_SOURCES = { HELMET: 'DIRECT_HELMET', BELT: 'DIRECT_BELT' }

export function isDirectDeviceForm(form) {
  return Boolean(DIRECT_DEVICE_SOURCES[form.type]) && form.source === DIRECT_DEVICE_SOURCES[form.type]
}

export function deviceConnectionErrors(form, existing = false) {
  if (existing || !isDirectDeviceForm(form)) return {}
  const number = String(form.deviceNumber || '').trim()
  return /^[A-Za-z0-9._-]{1,64}$/.test(number)
    ? {}
    : { deviceNumber: '请填写实际登录ID：1至64位字母、数字、点、下划线或连字符' }
}

export function deviceSubmission(form, existing = false) {
  const data = JSON.parse(JSON.stringify(form))
  if (existing) delete data.type
  if (existing || !isDirectDeviceForm(form)) {
    delete data.source
    delete data.deviceNumber
  } else {
    data.deviceNumber = String(data.deviceNumber || '').trim()
  }
  return data
}
