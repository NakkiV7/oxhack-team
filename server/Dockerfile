FROM node:24.22.1-bookworm-slim@sha256:55fb5f5a527ea2c5c4a95f963e48ef90aa38c7b346054fdc8ee9957a2b55d205

ENV NODE_ENV=production HOST=0.0.0.0 PORT=8787
WORKDIR /app/server
RUN chown node:node /app/server
USER node
COPY --chown=node:node server/package.json server/package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund && npm cache clean --force
COPY --chown=node:node server/src ./src
COPY --chown=node:node server/migrations ./migrations
COPY --chown=node:node Shared/Core/ExerciseCatalog.swift /app/Shared/Core/ExerciseCatalog.swift
COPY --chown=node:node Shared/Core/Resources/coach-guidance.json /app/Shared/Core/Resources/coach-guidance.json

EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 CMD ["node", "--input-type=module", "-e", "const r=await fetch('http://127.0.0.1:8787/health',{signal:AbortSignal.timeout(2000)});const h=await r.json();if(!r.ok||h.status!=='ok'||h.authenticationConfigured!==true)process.exit(1)"]
CMD ["node", "src/start.mjs"]
