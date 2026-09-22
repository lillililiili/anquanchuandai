import { createAdminService } from './service'
let provider
export function getAdminProvider() {
  if (!provider) provider = createAdminService({ storage: window.sessionStorage })
  return provider
}
