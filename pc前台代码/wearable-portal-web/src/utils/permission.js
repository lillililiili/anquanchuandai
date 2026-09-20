import pinia from '@/store'
import { useUserStore } from '@/store/user'

// 仅控制界面可见性；业务接口必须继续由后端鉴权及校验数据范围。
export function hasPermission(required) {
  const { permissions } = useUserStore(pinia)
  const values = Array.isArray(required) ? required : [required]
  return values.length > 0 && (permissions.includes('*:*:*') || values.some((value) => permissions.includes(value)))
}

export function hasRole(required) {
  const { roles } = useUserStore(pinia)
  const values = Array.isArray(required) ? required : [required]
  return values.length > 0 && (roles.includes('admin') || values.some((value) => roles.includes(value)))
}
