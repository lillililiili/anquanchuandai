# Acceptance adapter only. Never publish this image as the production media service.
FROM node:24.16.0-bookworm-slim@sha256:2c87ef9bd3c6a3bd4b472b4bec2ce9d16354b0c574f736c476489d09f560a203
WORKDIR /opt/wearable/helmet-media
COPY local-dev/helmet-media/package*.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund
COPY local-dev/helmet-media/*.mjs ./
COPY deploy/cluster/test/lab-media.mjs /opt/wearable/lab-media.mjs
RUN mkdir /data && chown node:node /data
USER node
ENTRYPOINT ["node", "/opt/wearable/lab-media.mjs"]
