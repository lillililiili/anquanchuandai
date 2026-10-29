import { prepareTracks, trackRange } from "./location.js";

export function createLocationApi(fetchImpl) {
  return {
    async history(personId, date, start, end, { signal, maxPages = 20, deviceId } = {}) {
      if (!personId && !deviceId) throw Error('请选择人员或设备');
      const range = trackRange(date, start, end);
      const rows = [], seenCursors = new Set();
      let cursor = "";
      for (let page = 0; page < maxPages; page++) {
        const query = new URLSearchParams({ ...(deviceId ? {deviceId} : {personId}), ...range, limit: "1000", ...(cursor ? { cursor } : {}) });
        const response = await fetchImpl(`/api/guardian/v1/locations/history?${query}`, { signal });
        const body = await response.json().catch(() => ({}));
        if (!response.ok) throw Error(body.message || "轨迹读取失败，请重试");
        if (!Array.isArray(body.rows)) throw Error("轨迹数据格式错误");
        rows.push(...body.rows);
        cursor = body.nextCursor;
        if (!cursor) return { points: prepareTracks(rows), unverified: rows.filter(row => !prepareTracks([row]).length).length, truncated: false };
        if (seenCursors.has(String(cursor))) throw Error("轨迹分页异常，请缩短查询时间");
        seenCursors.add(String(cursor));
      }
      return { points: prepareTracks(rows), truncated: true, unverified: rows.filter(row => !prepareTracks([row]).length).length };
    },
  };
}
