#!/usr/bin/env bash
set -euo pipefail
exec 3<>/dev/tcp/127.0.0.1/18084
printf 'GET /internal/cluster/ready HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n' >&3
IFS= read -r -t 3 status <&3
[[ $status == 'HTTP/1.1 200 '* || $status == 'HTTP/1.0 200 '* ]]
