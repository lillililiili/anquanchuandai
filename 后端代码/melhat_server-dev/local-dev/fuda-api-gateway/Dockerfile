FROM node:22-alpine
WORKDIR /app
COPY gateway.mjs package.json ./
USER node
ENV FUDA_GATEWAY_HOST=0.0.0.0 FUDA_GATEWAY_PORT=8080 FUDA_UPSTREAM_ORIGIN=http://backend:18084
EXPOSE 8080
CMD ["node", "gateway.mjs"]
