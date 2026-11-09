FROM cgr.dev/chainguard/node:latest-dev AS build

USER root

WORKDIR /app

COPY frontend/package.json ./package.json
COPY frontend/package-lock.json ./package-lock.json
COPY frontend/apps/web/package.json ./apps/web/package.json
COPY frontend/packages/api-sdk/package.json ./packages/api-sdk/package.json
COPY frontend/packages/tenant-session/package.json ./packages/tenant-session/package.json

RUN npm ci --ignore-scripts

COPY frontend/ ./

RUN npm run build --workspace @xydatalabs/orderprocessing-web

FROM cgr.dev/chainguard/node:latest AS final

WORKDIR /app

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=5022
ENV USE_HTTPS=false

COPY --from=build /app/apps/web/dist ./dist
COPY frontend/apps/web/server.mjs ./server.mjs
COPY frontend/apps/web/public-runtime-config.mjs ./public-runtime-config.mjs

EXPOSE 5022

CMD ["server.mjs"]
