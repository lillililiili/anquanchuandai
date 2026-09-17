#!/bin/bash
set -euo pipefail

mysql_exec() {
  mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" --default-character-set=utf8mb4 \
    --init-command="SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci" \
    "${MYSQL_DATABASE}"
}

echo "[melhat-init] ry_20230223.sql"
mysql_exec < /project-sql/ry_20230223.sql

echo "[melhat-init] quartz.sql"
mysql_exec < /project-sql/quartz.sql

echo "[melhat-init] melhat_demo.sql"
mysql_exec < /project-sql/melhat_demo.sql

for f in /project-sql/migrations/V*.sql; do
  echo "[melhat-init] $(basename "$f")"
  mysql_exec < "$f"
done

echo "[melhat-init] import finished"
