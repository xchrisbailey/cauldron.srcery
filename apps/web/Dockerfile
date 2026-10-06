# Build from the repo root: docker build -f apps/web/Dockerfile .
FROM oven/bun:1.4.2 AS manifests
WORKDIR /app
COPY package.json bun.lock ./
COPY apps/api/package.json apps/api/
COPY apps/web/package.json apps/web/
COPY packages/api-spec/package.json packages/api-spec/
COPY packages/db/package.json packages/db/
COPY packages/shared/package.json packages/shared/

FROM manifests AS build
RUN bun install --frozen-lockfile --ignore-scripts
COPY tsconfig.base.json tsconfig.json vite.config.ts ./
COPY packages ./packages
COPY apps/web ./apps/web
# Bun 1.4.2's FTL JIT miscompiles StyleX's media query parser once a build
# parses enough of them ("Invalid media query syntax" in random files). The
# image has no Node, so the build runs on Bun; drop this once Bun is fixed.
RUN BUN_JSC_useFTLJIT=0 bun run --cwd apps/web build

# The Start server bundle keeps its dependencies external, so the runtime
# stage carries web's production dependencies alongside the build output.
FROM manifests AS prod-deps
RUN bun install --frozen-lockfile --production --ignore-scripts --filter web

FROM oven/bun:1.4.2
ENV NODE_ENV=production
WORKDIR /app
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=prod-deps /app/apps/web/node_modules ./apps/web/node_modules
COPY --from=prod-deps /app/packages ./packages
COPY --from=build /app/packages ./packages
COPY package.json ./
COPY apps/web/package.json apps/web/server.ts apps/web/forward-headers.ts apps/web/security-headers.ts ./apps/web/
COPY --from=build /app/apps/web/dist ./apps/web/dist
USER bun
WORKDIR /app/apps/web
ENV PORT=3000
EXPOSE 3000
CMD ["bun", "server.ts"]
