#!/bin/bash
set -euo pipefail
cd /app
export HUSKY=0
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=2048}"
export VITE_APP_BASE_API=/dev-api
export VITE_APP_SOCKET_URL="${VITE_APP_SOCKET_URL:-ws://127.0.0.1:18084}"
export VITE_APP_TITLE="${VITE_APP_TITLE:-智能穿戴管理平台}"

npm install --ignore-scripts

echo "waiting for backend http://backend:18084/actuator/health"
for i in $(seq 1 180); do
  if wget -q -O /dev/null --timeout=2 http://backend:18084/actuator/health; then
    echo "backend is up"
    break
  fi
  sleep 2
done

echo "building pc production bundle"
npm run build:prod
exec npm run preview -- --host 0.0.0.0 --port 5175
