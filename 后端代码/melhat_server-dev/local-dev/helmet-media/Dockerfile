FROM node:22-bookworm-slim
COPY --from=python:3.11-slim-bookworm /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=helmet-media-apt rm -f /etc/apt/apt.conf.d/docker-clean && sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources && apt-get -o Acquire::Retries=3 update && apt-get -o Acquire::Retries=3 install -y --no-install-recommends ffmpeg ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package*.json ./
RUN npm ci --ignore-scripts --omit=dev --no-audit --no-fund
COPY *.mjs ./
CMD ["node", "server.mjs"]
