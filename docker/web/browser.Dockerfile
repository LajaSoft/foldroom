# syntax=docker/dockerfile:1
FROM node:26-bookworm-slim
WORKDIR /opt/browser
RUN npm install playwright-core
COPY docker/web/browser-test.mjs ./browser-test.mjs
CMD ["node", "browser-test.mjs"]
