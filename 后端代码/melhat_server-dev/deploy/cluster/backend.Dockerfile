FROM eclipse-temurin:17-jre-jammy@sha256:2a9eb226abb654c9d1f91b53cf638d20cb3abb726d1b18a67909c29515545469
WORKDIR /app
COPY ruoyi-admin/target/fdc-admin.jar /app/fdc-admin.jar
COPY deploy/cluster/probe.sh /app/probe.sh
RUN groupadd --gid 10001 wearable && useradd --uid 10001 --gid 10001 --no-create-home wearable \
    && mkdir -p /data/upload /data/tasks /data/hatfile /shared/files \
    && chown -R 10001:10001 /data /shared && chmod 0555 /app/probe.sh
USER 10001:10001
EXPOSE 18084
ENTRYPOINT ["java", "-Dfile.encoding=UTF-8", "-jar", "/app/fdc-admin.jar"]
