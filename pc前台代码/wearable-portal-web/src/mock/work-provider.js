import request from './request.js'
import { validateWorkResult } from '../utils/work-contract.js'
export async function getWorks(params, signal) { const r = await request.get('/mock-works/query', { params, signal }); validateWorkResult(r.data, params); return r }
export const getWorkEditor = (params, signal) => request.get('/mock-works/editor', { params, signal })
export const changeWork = (action, body, signal) => request.post('/mock-works/' + action, body, { signal })
