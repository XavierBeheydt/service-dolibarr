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

# Dump the database and archive the documents and custom modules into backups/
backup:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p backups
    stamp=$(date +%Y%m%d-%H%M%S)
    docker compose exec -T db sh -c 'exec mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" --single-transaction --routines --triggers "$MARIADB_DATABASE"' \
        | gzip > "backups/db-$stamp.sql.gz"
    docker compose exec -T web tar -C /var/www/documents -czf - . > "backups/documents-$stamp.tar.gz"
    docker compose exec -T web tar -C /var/www/html/custom -czf - . > "backups/custom-$stamp.tar.gz"
    echo "Backup written to backups/{db,documents,custom}-$stamp.*"

# Replace the data with backups/{db-<stamp>.sql[.gz],documents-<stamp>.tar.gz,custom-<stamp>.tar.gz}
[confirm("Replace the database, documents and custom modules with this backup? [y/N]")]
restore stamp:
    #!/usr/bin/env bash
    set -euo pipefail
    db=backups/db-{{ stamp }}.sql.gz
    [ -f "$db" ] || db=backups/db-{{ stamp }}.sql
    [ -f "$db" ] || { echo "No backups/db-{{ stamp }}.sql[.gz] found" >&2; exit 1; }
    echo "==> database from $db"
    docker compose exec -T db sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS \`$MARIADB_DATABASE\`; CREATE DATABASE \`$MARIADB_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"'
    case "$db" in *.gz) gunzip -c "$db" ;; *) cat "$db" ;; esac \
        | docker compose exec -T db sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE"'
    for dir in documents:/var/www/documents custom:/var/www/html/custom; do
        archive=backups/${dir%%:*}-{{ stamp }}.tar.gz
        [ -f "$archive" ] || { echo "==> no $archive, ${dir#*:} kept"; continue; }
        echo "==> ${dir#*:} from $archive"
        docker compose exec -T web sh -c "find ${dir#*:} -mindepth 1 -delete && tar -C ${dir#*:} -xzf - --no-same-owner && chown -R www-data:www-data ${dir#*:}" < "$archive"
    done
    # Without install.lock, the new web container migrates the database if it
    # comes from an older Dolibarr version, then locks the installation again
    docker compose exec -T web rm -f /var/www/documents/install.lock
    docker compose up -d --force-recreate

# Back up, pull the images and recreate the stack; the database is migrated when DOLIBARR_VERSION went up
upgrade: backup
    docker compose pull
    docker compose exec -T web rm -f /var/www/documents/install.lock
    docker compose up -d --force-recreate

# Remove the containers, the volumes (database, documents, custom modules) and .env
[confirm("Remove containers, database, documents and custom modules volumes, and .env? [y/N]")]
clean: env
    docker compose down --volumes --remove-orphans
    rm -f .env
