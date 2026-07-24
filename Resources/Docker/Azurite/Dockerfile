FROM node:20-alpine

ARG AZURITE_NPM_VERSION=3.35.0

RUN npm install --global "azurite@${AZURITE_NPM_VERSION}" \
    && npm cache clean --force

EXPOSE 10000 10001 10002

ENTRYPOINT ["azurite"]
