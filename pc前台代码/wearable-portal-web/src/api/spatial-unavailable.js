export const enabled = false
const closed = async () => { throw new Error('仅前端本地环境开放；未调用后端') }
export const read = closed
export const command = closed
