import { WEB_SOCKET_URL } from '@/common.config'

// import.meta.env.VITE_APP_SOCKET_URL

export function getSocketUrl(api: string) {
  return `${WEB_SOCKET_URL}/${api}`
}
