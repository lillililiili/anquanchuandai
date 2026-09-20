// No production fallback to mock business data.
export function getAdminProvider() {
  throw new Error('后台新业务尚未接入正式服务')
}
