# Build from the repo root: docker build -f apps/web/Dockerfile .
FROM oven/bun:1.4 AS build
WORKDIR /app
# Manifests first so the install layer is cached until dependencies change.
COPY package.json bun.lock ./
COPY apps/api/package.json apps/api/
COPY apps/web/package.json apps/web/
COPY packages/api-spec/package.json packages/api-spec/
COPY packages/db/package.json packages/db/
COPY packages/shared/package.json packages/shared/
RUN bun install --frozen-lockfile --ignore-scripts
COPY tsconfig.base.json tsconfig.json vite.config.ts ./
COPY packages ./packages
COPY apps/web ./apps/web
RUN bun run --cwd apps/web build

# The Start server bundle keeps its dependencies external, so the runtime
# stage carries the installed workspace alongside the build output.
FROM oven/bun:1.4
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./
COPY --from=build /app/packages ./packages
COPY --from=build /app/apps/web/node_modules ./apps/web/node_modules
COPY --from=build /app/apps/web/package.json ./apps/web/
COPY --from=build /app/apps/web/server.ts ./apps/web/
COPY --from=build /app/apps/web/dist ./apps/web/dist
USER bun
WORKDIR /app/apps/web
ENV PORT=3000
EXPOSE 3000
CMD ["bun", "server.ts"]
