import { mediaUrl } from './helmet-media.js';

// A renewed access ticket is still the same immutable media file. Compare its
// identity without the ticket, but always use the full authorized URL to load it.
export function mediaPreviewKey(media) {
  if (!media) return '';
  let source;
  if (media.url) {
    const safe = mediaUrl(media.url);
    const url = safe ? new URL(safe) : null;
    const renewableTicket = Boolean(url?.searchParams.get('token')) && media.source === 'DIRECT_HELMET'
      && /^\/helmet-media\/files\/[A-Za-z0-9_-]+$/.test(url.pathname);
    if (renewableTicket) {
      url.searchParams.delete('token');
    }
    source = ['url', url?.href || media.url, renewableTicket];
  } else if (media.blobId) {
    source = ['blob', media.blobId];
  } else {
    source = ['asset', media.asset || 'scene-boiler.png'];
  }
  return JSON.stringify([
    media.id, media.deviceId, media.siteId, media.station, media.source,
    String(media.kind || '').toLowerCase(), source,
  ]);
}
