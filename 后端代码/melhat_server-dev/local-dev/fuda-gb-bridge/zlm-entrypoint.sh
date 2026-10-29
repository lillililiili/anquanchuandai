#!/bin/sh
set -eu
[ "${GB_ENABLED:-false}" = true ] || { echo 'GB media sidecar disabled'; exit 0; }
: "${GB_ZLM_SECRET:?GB_ZLM_SECRET required}"
[ "${#GB_ZLM_SECRET}" -ge 32 ] || exit 1
case "$GB_ZLM_SECRET" in *[!A-Za-z0-9_-]*) exit 1;; esac
umask 077
cat > /tmp/fuda-zlm.ini <<EOF
[api]
apiDebug=0
secret=${GB_ZLM_SECRET}
[general]
listen_ip=127.0.0.1
mediaServerId=fuda-gb-bridge
enableVhost=0
maxStreamWaitMS=5000
[http]
port=18194
sslport=0
dirMenu=0
allow_ip_range=127.0.0.1
allow_origins=
rootPath=/tmp/empty-www
[protocol]
enable_audio=1
add_mute_audio=0
enable_rtmp=1
enable_rtsp=0
enable_hls=0
enable_mp4=0
enable_ts=0
enable_fmp4=0
[rtmp]
port=0
sslport=0
[rtsp]
port=0
sslport=0
[rtp_proxy]
port=0
[rtc]
port=0
tcpPort=0
signalingPort=0
signalingSslPort=0
icePort=0
iceTcpPort=0
[srt]
port=0
[shell]
port=0
[hook]
enable=0
EOF
mkdir -p /tmp/empty-www
exec /opt/media/bin/MediaServer -c /tmp/fuda-zlm.ini -l 2
