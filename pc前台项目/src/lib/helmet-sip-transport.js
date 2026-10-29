// This deployment terminates public TLS at Caddy, then forwards plain WS to
// FreeSWITCH. Sofia compares Via with that inner transport and silently drops
// WSS Via requests. Keep browser TLS intact and describe only the inner hop.
export function helmetSipTransportOptions(SIP, server) {
  let endpoint;
  try { endpoint = new URL(server); } catch { return {}; }
  if (endpoint.origin !== 'wss://lingzhiaide.com' || endpoint.pathname !== '/helmet-media/sip'
      || endpoint.username || endpoint.password || endpoint.search || endpoint.hash) return {};
  class HelmetProxyTransport extends SIP.Web.Transport {
    get protocol() { return 'WS'; }
  }
  return { transportConstructor: HelmetProxyTransport };
}
