import { createTransport } from './transport.js'
import { readDataset, transact } from './storage.js'
const request = createTransport({ read: readDataset, update: transact, session: sessionStorage })
export const setUnauthorizedHandler = fn => request.setUnauthorizedHandler(fn)
export const expireSession = () => request.expire()
export default request
