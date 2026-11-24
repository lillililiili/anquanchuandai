import { authFetch } from './auth.js';

export function splitMediaPath(value) {
  if (typeof value !== 'string' || !/^\/api\/guardian\/v1\/split\/devices\/[A-Za-z0-9._%~-]+\/files\/[A-Za-z0-9_-]+$/.test(value)) throw Error('设备文件地址无效');
  return value;
}
export async function loadSplitMedia(media, { fetchImpl = authFetch, signal } = {}) {
  const response = await fetchImpl(splitMediaPath(media?.url), { signal });
  if (!response.ok) throw Error(response.status === 401 || response.status === 403 ? '无权查看此设备文件，请刷新权限' : '设备文件暂时不可用，请重试');
  const blob = await response.blob();
  if (!/^(image|video|audio)\//.test(blob.type)) throw Error('设备未返回可预览的媒体文件');
  return blob;
}
