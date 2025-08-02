# Production Deployment Guide

## Overview

This Docker setup builds both NestJS microservices (API Gateway and Products Service) from source during the Docker build process, making it suitable for production deployments where the source code is cloned from Git.

## Architecture

```
┌─────────────────┐    gRPC     ┌─────────────────┐
│   API Gateway   │◄────────────┤ Products Service │
│   Port: 3000    │             │   gRPC: 5001    │
│   HTTP + REST   │             │   gRPC Only     │
└─────────────────┘             └─────────────────┘
```

## Production Deployment

### Prerequisites

- Docker and Docker Compose installed
- Access to GitHub repository: `github.com/eliotmeurillon/NestJS-Microservice-with-gRPC.git`

### Quick Deploy

```bash
# Clone the repository
git clone https://github.com/eliotmeurillon/NestJS-Microservice-with-gRPC.git
cd NestJS-Microservice-with-gRPC

# Deploy with Docker Compose
docker-compose up -d --build
```

### Dokploy/Production Platform

For deployment platforms like Dokploy:

1. **Repository**: `github.com/eliotmeurillon/NestJS-Microservice-with-gRPC.git`
2. **Compose Type**: `docker-compose`
3. **File**: `docker-compose.yml`
4. **Build**: Automatic (builds from source)

### Key Features

✅ **Multi-stage build**: Optimized for production
✅ **Source code compilation**: Builds applications from source during Docker build
✅ **Monorepo support**: Uses Nx to build specific applications
✅ **gRPC communication**: Internal service-to-service communication
✅ **Health checks**: HTTP health check for API Gateway
✅ **Security**: Non-root user execution
✅ **Proto file sharing**: Shared protocol buffers between services

## Services

### API Gateway

- **Port**: 3000
- **Type**: HTTP REST API
- **Health Check**: `GET /api`
- **Environment Variables**:
  - `NODE_ENV=production`
  - `PORT=3000`
  - `PRODUCTS_SERVICE_URL=products:5001`

### Products Service

- **Port**: 5001 (gRPC)
- **Type**: gRPC Microservice
- **Environment Variables**:
  - `NODE_ENV=production`
  - `GRPC_PORT=5001`

## Build Process

The Dockerfile uses a multi-stage build:

1. **Builder Stage**:

   - Installs all dependencies (including dev)
   - Generates TypeScript types from proto files
   - Builds the specific application using Nx

2. **Production Stage**:
   - Uses only production dependencies
   - Copies built application from builder
   - Runs as non-root user

## Environment Variables

| Variable               | Service     | Default         | Description            |
| ---------------------- | ----------- | --------------- | ---------------------- |
| `NODE_ENV`             | Both        | `production`    | Node.js environment    |
| `PORT`                 | API Gateway | `3000`          | HTTP server port       |
| `GRPC_PORT`            | Products    | `5001`          | gRPC server port       |
| `PRODUCTS_SERVICE_URL` | API Gateway | `products:5001` | gRPC client connection |

## Networking

- **Network**: `nestjs-microservices-network` (bridge)
- **Service Discovery**: Docker Compose DNS resolution
- **External Access**: Only API Gateway (port 3000)
- **Internal Communication**: gRPC on port 5001

## Health Monitoring

### API Gateway Health Check

```bash
curl http://localhost:3000/api
```

### Container Status

```bash
docker-compose ps
docker-compose logs -f
```

## Scaling

To scale individual services:

```bash
# Scale API Gateway
docker-compose up -d --scale api-gateway=3

# Note: Products service uses gRPC, scaling requires load balancing
```

## Troubleshooting

### Common Issues

1. **Build Failures**: Ensure all source files are included and not in `.dockerignore`
2. **gRPC Connection Issues**: Verify service names and ports in environment variables
3. **Proto File Errors**: Ensure proto files are properly copied and generated

### Debug Commands

```bash
# Check service logs
docker-compose logs api-gateway
docker-compose logs products

# Check service health
docker-compose exec api-gateway wget -qO- http://localhost:3000/api

# Check gRPC connectivity (inside container)
docker-compose exec api-gateway ping products
```

## Security Notes

- Both services run as non-root user (`nestjs`)
- Only API Gateway exposed to external traffic
- Production dependencies only in final image
- No development tools in production image

## Performance Optimizations

- Multi-stage build reduces final image size
- PNPM for faster package installation
- Alpine Linux base image for smaller footprint
- Layer caching optimized build order
