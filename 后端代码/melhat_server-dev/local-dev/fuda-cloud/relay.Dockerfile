FROM node:22-alpine
WORKDIR /app
COPY tcp-relay.mjs ./
USER node
CMD ["node", "tcp-relay.mjs"]
