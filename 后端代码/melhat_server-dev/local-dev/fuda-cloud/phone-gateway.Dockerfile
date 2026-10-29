FROM node:22-alpine
WORKDIR /app
COPY gateway.mjs ./
USER node
CMD ["node", "gateway.mjs"]
