# Docker Setup for NestJS Microservices

This workspace now includes Docker and Docker Compose configuration for running your NestJS microservices.

## Quick Start

### Production Mode

```bash
# Start all services in production mode
nx docker-compose:up

# View logs
nx docker-compose:logs

# Stop services
nx docker-compose:down
```

### Development Mode

```bash
# Start all services in development mode with hot reloading
nx docker-compose:dev

# Stop development services
nx docker-compose:dev:down
```

## Individual Service Commands

### Build individual Docker images

```bash
# Build API Gateway
nx docker-build api-gateway

# Build Products Service
nx docker-build products
```

### Run individual services

```bash
# Run API Gateway
nx docker-run api-gateway

# Run Products Service
nx docker-run products
```

## Available Services

When running with Docker Compose:

- **API Gateway**: http://localhost:3000
- **Products Service**: http://localhost:3001
- **gRPC Communication**: Services communicate internally via gRPC on port 5001

## Files Created

- `Dockerfile` - Multi-service production Dockerfile
- `Dockerfile.dev` - Development Dockerfile with hot reloading
- `docker-compose.yml` - Production service orchestration
- `docker-compose.dev.yml` - Development service orchestration
- `.dockerignore` - Optimizes Docker builds

## Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   API Gateway   │    │  Products Svc   │
│   Port: 3000    │────│   Port: 3001    │
│                 │gRPC│   gRPC: 5001    │
└─────────────────┘    └─────────────────┘
```

The API Gateway acts as the entry point and communicates with the Products service via gRPC protocol.

## Development Features

- Hot reloading in development mode
- Debug ports exposed (9228 for API Gateway, 9229 for Products)
- Volume mounting for real-time code changes
- Proto file sharing between services

This setup is production-ready and includes health checks, proper networking, and service dependencies.
