FROM node:16 as builder

WORKDIR /app

COPY package*.json ./

RUN git submodule update --init --recursive \
    && cd ./node-sqlite3 \
    && npm install --omit=dev \
    && npm audit --fix \
    && cd .. \
    && npm install -g pnpm \
    && pnpm install --production

COPY . .

RUN mkdir -p ./public ./data \
    && cd ./client \
    && npm install -g pnpm \
    && pnpm install --production \
    && pnpm run build \
    && cd .. \
    && mv ./client/build/* ./public \
    && rm -rf ./client

FROM node:16-alpine

COPY --from=builder /app /app

WORKDIR /app

EXPOSE 80:5005

ENV NODE_ENV=production

CMD ["sh", "-c", "chown -R node /app/data && node server.js"]