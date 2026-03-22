# local-network-multisite Makefile
#
# Usage:
#   make up      — Create the shared network (if absent) and start Traefik
#   make down    — Stop Traefik (network is kept so downstream projects remain routable)
#   make logs    — Follow Traefik logs
#   make certs   — Generate local TLS certificates via mkcert
#   make ps      — Show running service status
#   make clean   — Stop Traefik and remove the shared network

# Load .env if present (does not override existing shell variables)
ifneq (,$(wildcard .env))
  include .env
  export
endif

TRAEFIK_NETWORK ?= traefik-net
COMPOSE         := docker compose

.PHONY: up down logs certs ps clean help

## up: Create shared network (if absent) and start Traefik in detached mode
up:
	@echo ">>> Ensuring Docker network '$(TRAEFIK_NETWORK)' exists..."
	@docker network inspect $(TRAEFIK_NETWORK) > /dev/null 2>&1 \
		|| docker network create $(TRAEFIK_NETWORK)
	@echo ">>> Starting Traefik..."
	$(COMPOSE) up -d
	@echo ""
	@echo "Traefik is up. Dashboard: https://traefik.local"
	@echo "(make sure traefik.local is in /etc/hosts → 127.0.0.1)"

## down: Stop Traefik (the shared network is intentionally preserved)
down:
	@echo ">>> Stopping Traefik (network '$(TRAEFIK_NETWORK)' is preserved)..."
	$(COMPOSE) down

## logs: Follow Traefik container logs
logs:
	$(COMPOSE) logs -f traefik

## certs: Generate local TLS certificates using mkcert
certs:
	@bash scripts/generate-certs.sh

## ps: Show status of services defined in this compose file
ps:
	$(COMPOSE) ps

## clean: Stop Traefik AND remove the shared Docker network
clean: down
	@echo ""
	@printf ">>> Remove Docker network '$(TRAEFIK_NETWORK)'? This will break downstream projects. [y/N] " \
		&& read ans && [ "$${ans:-N}" = "y" ] \
		&& docker network rm $(TRAEFIK_NETWORK) && echo "Network removed." \
		|| echo "Aborted — network kept."

## help: List available targets
help:
	@grep -E '^## ' Makefile | sed 's/^## //' | column -t -s ':'
