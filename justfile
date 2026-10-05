# Copyright (c) 2026 Xavier Beheydt <xavier.beheydt@gmail.com>

# Every service repo provides the recipes up, down, start, stop and ps,
# so the parent repo can drive all of them the same way.

# List available recipes
default:
    @just --list

# Create .env from .env.example if it does not exist yet
env:
    @test -f .env || { cp .env.example .env && echo "Created .env from .env.example"; }

# Start the stack (creates .env); Traefik must be up, it owns the proxy network
up: env
    @docker network inspect proxy >/dev/null 2>&1 || { echo "The proxy network is missing, start Traefik first" >&2; exit 1; }
    docker compose up -d

# Stop and remove the containers (the volumes are kept)
down:
    docker compose down

# Start the existing containers
start:
    docker compose start

# Stop the containers without removing them
stop:
    docker compose stop

# Show the containers of the stack
ps:
    docker compose ps

# Follow the logs
logs:
    docker compose logs -f

# Remove the containers, the volumes (database, documents, custom modules) and .env
[confirm("Remove containers, database, documents and custom modules volumes, and .env? [y/N]")]
clean: env
    docker compose down --volumes --remove-orphans
    rm -f .env
