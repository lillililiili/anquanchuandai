// HTTP Date is the trusted API server's clock, rounded down to whole seconds.
// Use that second's upper bound: precision is <1s, never an arbitrary grace
// period based on the user's wall clock. Elapsed time uses a monotonic clock.
export function createServerClock({
  wallNow = () => Date.now(),
  monotonicNow = () => globalThis.performance.now(),
} = {}) {
  let anchor = null;
  let latestRequestStart = -Infinity;
  const now = () => anchor == null ? wallNow()
    : anchor.serverTime + Math.max(0, monotonicNow() - anchor.receivedAt);
  return {
    now,
    syncFromHttpDate(dateHeader, requestStartedAt = monotonicNow()) {
      if (typeof dateHeader !== 'string' || !dateHeader.trim()) return false;
      const stamp = Date.parse(dateHeader);
      const receivedAt = monotonicNow();
      if (!Number.isFinite(stamp) || !Number.isFinite(receivedAt)
        || !Number.isFinite(requestStartedAt) || requestStartedAt > receivedAt
        || requestStartedAt < latestRequestStart) return false;
      const dateSecondEnd = Math.floor(stamp / 1000) * 1000 + 999;
      const previous = anchor == null ? -Infinity : now();
      anchor = { serverTime: Math.max(previous, dateSecondEnd), receivedAt };
      latestRequestStart = requestStartedAt;
      return true;
    },
    reset() { anchor = null; latestRequestStart = -Infinity; },
    get synchronized() { return anchor != null; },
  };
}

export const serverClock = createServerClock();
export const serverNow = () => serverClock.now();
export const syncServerTime = (dateHeader, requestStartedAt) => serverClock.syncFromHttpDate(dateHeader, requestStartedAt);
export const resetServerClock = () => serverClock.reset();
