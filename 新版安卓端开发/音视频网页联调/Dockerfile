FROM node:22-bookworm
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY server.mjs ./
COPY business-lab.mjs ./
COPY video ./video
COPY public ./public
USER node
ENV PORT=18766
EXPOSE 18766
CMD ["node", "server.mjs"]
