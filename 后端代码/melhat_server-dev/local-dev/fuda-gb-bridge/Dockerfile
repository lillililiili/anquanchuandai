FROM node:22.14.0-alpine
WORKDIR /app
COPY package.json *.mjs ./
RUN mkdir -p /app/data && chown -R node:node /app
USER node
CMD ["node", "server.mjs"]
