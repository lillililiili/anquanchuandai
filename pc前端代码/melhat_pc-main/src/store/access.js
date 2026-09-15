export const ALL_PERMISSION = '*:*:*'

export function mergeAccessValues(current = [], incoming = []) {
  return Array.from(new Set([
    ...(Array.isArray(current) ? current : []),
    ...(Array.isArray(incoming) ? incoming : [])
  ]))
}

export function hasAccessPermission(permissions = [], permission) {
  return permissions.includes(ALL_PERMISSION) || permissions.includes(permission)
}
