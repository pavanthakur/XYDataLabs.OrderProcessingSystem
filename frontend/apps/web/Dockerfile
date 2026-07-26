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

ARG VITE_ORDERPROCESSING_API_BASE_URL=
ENV VITE_ORDERPROCESSING_API_BASE_URL=$VITE_ORDERPROCESSING_API_BASE_URL
ARG VITE_KEYCLOAK_AUTHORITY=
ENV VITE_KEYCLOAK_AUTHORITY=$VITE_KEYCLOAK_AUTHORITY
ARG VITE_KEYCLOAK_REALM=
ENV VITE_KEYCLOAK_REALM=$VITE_KEYCLOAK_REALM
ARG VITE_KEYCLOAK_CLIENT_ID=
ENV VITE_KEYCLOAK_CLIENT_ID=$VITE_KEYCLOAK_CLIENT_ID
RUN npm run build --workspace @xydatalabs/orderprocessing-web

FROM cgr.dev/chainguard/node:latest AS final

WORKDIR /app

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=5022
ENV USE_HTTPS=false

COPY --from=build /app/apps/web/dist ./dist
COPY frontend/apps/web/server.mjs ./server.mjs

EXPOSE 5022

CMD ["server.mjs"]
