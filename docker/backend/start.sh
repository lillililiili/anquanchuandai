#!/bin/bash
set -euo pipefail
cd /workspace
mkdir -p /data/upload /data/hatfile /data/taskPackage
if [ ! -f /workspace/ruoyi-admin/target/fdc-admin.jar ]; then
  mvn -pl ruoyi-admin -am package -DskipTests
fi
exec java -Xms256m -Xmx1024m -Duser.timezone=Asia/Shanghai \
  -jar /workspace/ruoyi-admin/target/fdc-admin.jar
