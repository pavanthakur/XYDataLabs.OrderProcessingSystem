FROM node:20-alpine AS build

WORKDIR /app

COPY frontend/package.json ./package.json
COPY frontend/package-lock.json ./package-lock.json
COPY frontend/apps/web/package.json ./apps/web/package.json
COPY frontend/packages/api-sdk/package.json ./packages/api-sdk/package.json
COPY frontend/packages/tenant-session/package.json ./packages/tenant-session/package.json

RUN npm ci

COPY frontend/ ./

ARG VITE_ORDERPROCESSING_API_BASE_URL=
ENV VITE_ORDERPROCESSING_API_BASE_URL=$VITE_ORDERPROCESSING_API_BASE_URL

RUN npm run build --workspace @xydatalabs/orderprocessing-web

FROM node:20-alpine AS final

WORKDIR /app

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=5022
ENV USE_HTTPS=false

COPY --from=build /app/apps/web/dist ./dist
COPY frontend/apps/web/server.mjs ./server.mjs

EXPOSE 5022

CMD ["node", "server.mjs"]
