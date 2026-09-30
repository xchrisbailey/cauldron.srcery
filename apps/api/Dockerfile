# Build from the repo root: docker build -f apps/api/Dockerfile .
FROM oven/bun:1.4.2 AS deps
WORKDIR /app
# Manifests first so the install layer is cached until dependencies change.
COPY package.json bun.lock ./
COPY apps/api/package.json apps/api/
COPY apps/web/package.json apps/web/
COPY packages/api-spec/package.json packages/api-spec/
COPY packages/db/package.json packages/db/
COPY packages/shared/package.json packages/shared/
RUN bun install --frozen-lockfile --production --ignore-scripts --filter api

FROM oven/bun:1.4.2
ENV NODE_ENV=production
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/apps/api/node_modules ./apps/api/node_modules
COPY --from=deps /app/packages ./packages
COPY package.json ./
COPY packages ./packages
COPY apps/api ./apps/api
# Without DATABASE_URL the API falls back to PGlite. Set DATABASE_URL in any
# real deployment, or mount a volume at PGLITE_DATA_DIR; an unset data dir is in-memory.
RUN mkdir -p apps/api/.data && chown -R bun:bun apps/api/.data
USER bun
WORKDIR /app/apps/api
ENV PORT=3001
EXPOSE 3001
CMD ["bun", "src/main.ts"]
