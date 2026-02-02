# Stage: monolith-builder
# Purpose: Uses the Rust image to build monolith
# Notes:
#  - Fine to leave extra here, as only the resulting binary is copied out
FROM docker.io/rust:1.86-bullseye AS monolith-builder

RUN set -eux && cargo install --locked monolith

# Stage: main-app
# Purpose: Compiles the frontend and
# Notes:
#  - Nothing extra should be left here.  All commands should cleanup
FROM node:20.19.6-bullseye-slim AS main-app

ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0

ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0

ENV PRISMA_HIDE_UPDATE_MESSAGE=1

ARG DEBIAN_FRONTEND=noninteractive

RUN mkdir /data

WORKDIR /data

RUN corepack enable

COPY ./apps/web/package.json ./apps/web/playwright.config.ts ./apps/web/

COPY ./apps/worker/package.json ./apps/worker/

COPY ./packages ./packages

COPY ./pnpm-lock.yaml ./package.json ./

RUN --mount=type=cache,target=/root/.pnpm-store \
    set -eux && \
    pnpm install --frozen-lockfile && \
    # Install curl for healthcheck, and ca-certificates to prevent monolith from failing to retrieve resources due to invalid certificates
    apt-get update && \
    apt-get install -yqq --no-install-recommends curl ca-certificates && \
    apt-get autoremove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy the compiled monolith binary from the builder stage
COPY --from=monolith-builder /usr/local/cargo/bin/monolith /usr/local/bin/monolith

RUN set -eux && \
    apt-get clean && \
    pnpm store prune || true

COPY . .

RUN pnpm run prisma:generate && \
    pnpm run web:build && \
    rm -rf apps/web/.next/cache

HEALTHCHECK --interval=30s \
            --timeout=5s \
            --start-period=10s \
            --retries=3 \
            CMD [ "/usr/bin/curl", "--silent", "--fail", "http://127.0.0.1:3000/" ]

EXPOSE 3000

CMD ["sh", "-c", "pnpm run prisma:deploy && pnpm run concurrently:start"]
