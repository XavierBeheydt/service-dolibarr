# Copyright (c) 2026 Xavier Beheydt <xavier.beheydt@gmail.com>

# Every service repo provides the recipes up, down, start, stop and ps,
# so the parent repo can drive all of them the same way.

# List available recipes
default:
    @just --list

# Create .env from .env.example if it does not exist yet
env:
    @test -f .env || { cp .env.example .env && echo "Created .env from .env.example"; }

# Generate the missing secrets in secrets/ (existing ones are kept)
secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p secrets
    chmod 700 secrets
    # name:value, where a number means that many random bytes, in hex
    for spec in db_user:dolibarr db_password:24 db_root_password:24 doli_instance_unique_id:32 doli_admin_password:12; do
        name=${spec%%:*}
        value=${spec#*:}
        file=secrets/$name
        [ -s "$file" ] && continue
        # World-readable inside the folder: MariaDB reads its secrets as the mysql user
        if [[ $value =~ ^[0-9]+$ ]]; then value=$(openssl rand -hex "$value"); fi
        (umask 022; printf '%s' "$value" > "$file")
        echo "Created $file"
    done

# Start the stack (creates .env and the secrets); Traefik must be up, it owns the proxy network
up: env secrets
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

# Dump the database and archive the documents into backups/ (the stack must be running)
backup:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p backups
    stamp=$(date +%Y%m%d-%H%M%S)
    docker compose exec -T db sh -c 'exec mariadb-dump -u"$(cat "$MARIADB_USER_FILE")" -p"$(cat "$MARIADB_PASSWORD_FILE")" --single-transaction --routines --triggers "$MARIADB_DATABASE"' \
        | gzip > "backups/db-$stamp.sql.gz"
    docker compose exec -T web tar -C /var/www/documents -czf - . > "backups/documents-$stamp.tar.gz"
    echo "Backup written to backups/{db,documents}-$stamp.*"

# Remove the containers, the volumes (database, documents), .env and secrets/ (backups/ is kept)
[confirm("Remove containers, database and documents volumes, .env and secrets/? [y/N]")]
clean: env secrets
    docker compose down --volumes --remove-orphans
    rm -rf .env secrets
