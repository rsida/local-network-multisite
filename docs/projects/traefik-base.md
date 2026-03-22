# Project Brief: Traefik Base Infrastructure

## Overview

This project provides a shared Docker-based reverse proxy infrastructure using Traefik v3.
It acts as the single network gateway for all local development projects, handling TLS
termination and HTTP/HTTPS routing without requiring each project to expose ports directly.

## Goals

- Run a single Traefik instance that always listens on ports 80 and 443 on the host
- Allow independent projects (separate git repositories) to connect to this infrastructure
- Support configurable local domain names per project (e.g., `myapp.local`, `api.local`)
- Centralize TLS certificate management (self-signed or mkcert-based for local development)
- Enforce a strict pattern: downstream projects never bind host ports themselves

## Constraints

- Docker Compose v2 is the orchestration tool
- Traefik v3 is the reverse proxy
- The shared Docker network must be external and named so other projects can reference it
- TLS certificates for `.local` domains must work in local browsers (mkcert recommended)
- The solution must be simple to start (`docker compose up -d`) and idempotent

## Non-Goals

- Production deployment (no Let's Encrypt ACME for production domains in scope)
- Service discovery beyond Docker label-based routing
- Load balancing across multiple hosts

## Stakeholders

- Developer (Romain): primary user, runs this on a local Linux/WSL2 workstation

## Deliverables

1. `docker-compose.yml` — Traefik service definition
2. `traefik/traefik.yml` — static Traefik configuration
3. `traefik/dynamic/` — dynamic configuration directory (TLS stores, middlewares)
4. `certs/` — directory for local TLS certificates (gitignored)
5. `Makefile` — developer convenience targets (`up`, `down`, `logs`, `certs`)
6. `.env.example` — documented environment variables
7. `README.md` — setup and usage guide

## Success Criteria

- `docker compose up -d` starts Traefik listening on 80 and 443
- A sample downstream project using only Docker labels and the shared network resolves
  its `.local` domain over HTTPS without browser certificate warnings
- Adding a new project requires zero changes to this repository
