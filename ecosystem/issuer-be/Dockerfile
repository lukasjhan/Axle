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

RUN addgroup --system --gid 1001 issuer && \
    adduser --system --uid 1001 issuer

WORKDIR /app

COPY --chown=issuer:issuer package.json pnpm-lock.yaml ./

RUN corepack install && pnpm install --frozen-lockfile --prod --ignore-scripts

COPY --from=builder --chown=issuer:issuer /app/dist ./dist
COPY --from=builder --chown=issuer:issuer /app/drizzle ./drizzle

USER issuer

EXPOSE 3400

CMD ["node", "dist/main"]
