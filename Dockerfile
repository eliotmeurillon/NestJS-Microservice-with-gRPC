# Multi-stage Dockerfile for NestJS microservices with Nx
ARG APP_NAME=products

# Build stage
FROM docker.io/node:lts-alpine AS builder

WORKDIR /app

# Install protoc (Protocol Buffer compiler) and ts-proto for generating types
RUN apk add --no-cache protobuf-dev && npm install -g ts-proto

# Copy package files
COPY package.json package-lock.json ./

# Install all dependencies (including dev dependencies for building)
RUN npm ci

# Copy source code
COPY . .

# Override the problematic protoc script with system protoc
RUN echo '#!/bin/sh' > /usr/local/bin/protoc-wrapper && \
    echo 'protoc --plugin=protoc-gen-ts_proto=/usr/local/lib/node_modules/ts-proto/protoc-gen-ts_proto "$@"' >> /usr/local/bin/protoc-wrapper && \
    chmod +x /usr/local/bin/protoc-wrapper

# Replace the package.json script to use our wrapper
RUN node -e 'const fs = require("fs"); const pkg = JSON.parse(fs.readFileSync("package.json", "utf8")); pkg.scripts["generate-proto-types"] = "/usr/local/bin/protoc-wrapper --ts_proto_out=./types/ ./proto/*.proto --ts_proto_opt=nestJs=true"; fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2));'

# Generate proto types using system protoc
RUN protoc --plugin=protoc-gen-ts_proto=/usr/local/lib/node_modules/ts-proto/protoc-gen-ts_proto \
    --ts_proto_out=./types/ \
    --ts_proto_opt=nestJs=true \
    ./proto/*.proto

# Build the specific application
ARG APP_NAME
RUN npx nx build ${APP_NAME} --skip-nx-cache

# Production stage
FROM docker.io/node:lts-alpine AS production

ENV HOST=0.0.0.0
ENV PORT=3000

WORKDIR /app

# Create user and group
RUN addgroup --system nestjs && \
          adduser --system -G nestjs nestjs

# Copy package files and install only production dependencies
COPY package.json package-lock.json ./
RUN npm ci --only=production && npm cache clean --force

# Copy built application from builder stage
ARG APP_NAME
COPY --from=builder /app/dist/apps/${APP_NAME} ./app/
COPY --from=builder /app/proto ./proto/
COPY --from=builder /app/types ./types/

# Change ownership to nestjs user
RUN chown -R nestjs:nestjs .

# Switch to non-root user
USER nestjs

# Expose default port
EXPOSE 3000

CMD [ "node", "app/main.js" ]
