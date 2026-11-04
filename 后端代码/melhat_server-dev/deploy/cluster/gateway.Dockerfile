FROM node:24.16.0-bookworm-slim@sha256:2c87ef9bd3c6a3bd4b472b4bec2ce9d16354b0c574f736c476489d09f560a203
WORKDIR /opt/wearable
COPY local-dev/protocol-cluster/package*.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund && npm cache clean --force
COPY local-dev/protocol-cluster/*.mjs ./protocol-cluster/
COPY local-dev/device-gateway/*.mjs ./device-gateway/
COPY local-dev/belt-device-gateway/*.mjs ./belt-device-gateway/
COPY local-dev/wear-api-gateway/gateway.mjs ./wear-api-gateway/
COPY local-dev/fuda-api-gateway/gateway.mjs ./fuda-api-gateway/
COPY local-dev/helmet-media/auth.mjs local-dev/helmet-media/spool.mjs ./helmet-media/
RUN mkdir -p /opt/wearable/device-gateway/.local/upload-temp \
    && chown -R node:node /opt/wearable/device-gateway/.local
USER node
EXPOSE 8080
ENTRYPOINT ["node", "/opt/wearable/protocol-cluster/cli.mjs"]
