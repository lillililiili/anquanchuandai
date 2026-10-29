FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY *.mjs ./
RUN mkdir -p /app/.local && chown -R node:node /app
USER node
CMD ["node", "cli.mjs"]
