# Eve Horizon Fullstack Example - Web Dockerfile
# Multi-stage build: Node for build, nginx for serving

# =============================================================================
# Stage 1: Build
# =============================================================================
FROM node:22-slim AS build

WORKDIR /app
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable && corepack prepare pnpm@10 --activate

COPY package.json ./
RUN pnpm install --frozen-lockfile 2>/dev/null || pnpm install

COPY tsconfig.json vite.config.ts index.html ./
COPY src ./src
RUN pnpm build

# =============================================================================
# Stage 2: Production (nginx)
# =============================================================================
FROM nginx:alpine AS production

# OCI image labels — links this package to the source repo in GHCR
LABEL org.opencontainers.image.source="https://github.com/eve-horizon/eve-horizon-fullstack-example"
LABEL org.opencontainers.image.description="Web frontend"

# Copy built assets from build stage
COPY --from=build /app/dist /usr/share/nginx/html

# SPA routing plus an /api/ proxy to the private API. The image renders
# templates into conf.d at start-up, filling in API_SERVICE_HOST.
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
ENV API_SERVICE_HOST=api

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
