# Build stage
FROM node:24-alpine AS builder

RUN corepack enable

WORKDIR /app

COPY package.json pnpm-lock.yaml ./

RUN corepack install && pnpm install --frozen-lockfile

COPY . .

RUN pnpm build

# Production stage
FROM node:24-alpine AS production

RUN corepack enable

RUN addgroup --system --gid 1001 wp && \
    adduser --system --uid 1001 wp

WORKDIR /app

COPY --chown=wp:wp package.json pnpm-lock.yaml ./

RUN corepack install && pnpm install --frozen-lockfile --prod --ignore-scripts

COPY --from=builder --chown=wp:wp /app/dist ./dist
COPY --from=builder --chown=wp:wp /app/drizzle ./drizzle

USER wp

EXPOSE 3200

CMD ["node", "dist/main"]
