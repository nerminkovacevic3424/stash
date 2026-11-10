FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY server.js ./
COPY lib ./lib
ENV NODE_ENV=production PORT=8787
EXPOSE 8787
USER node
CMD ["node", "server.js"]
