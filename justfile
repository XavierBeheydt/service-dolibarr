# Copyright (c) 2026 Xavier Beheydt <xavier.beheydt@gmail.com>

# Every service repo provides the recipes up, down, start, stop and ps,
# so the parent repo can drive all of them the same way.

# List available recipes
default:
    @just --list

# Create .env from .env.example if it does not exist yet
env:
    @test -f .env || { cp .env.example .env && echo "Created .env from .env.example"; }

# Generate the missing secrets in secrets/ with random values (existing ones are kept)
secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p secrets
    chmod 700 secrets
    for spec in db_password:24 db_root_password:24 doli_instance_unique_id:32 doli_admin_password:12 doli_cron_key:16; do
        file=secrets/${spec%%:*}
        [ -s "$file" ] && continue
        # World-readable inside the folder: MariaDB reads its secrets as the mysql user
        (umask 022; openssl rand -hex "${spec#*:}" | tr -d '\n' > "$file")
        echo "Created $file"
    done

# Create the shared internal ingress network if it is missing
networks:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! internal=$(docker network inspect -f '{{{{.Internal}}' ingress 2>/dev/null); then
        docker network create --internal ingress >/dev/null
        echo "Created the internal ingress network"
    elif [ "$internal" != true ]; then
        echo "The ingress network is not internal: stop every stack, run \`docker network rm ingress\`, then start them again" >&2
        exit 1
    fi

# Start the stack (creates .env, the secrets and the ingress network)
up: env secrets networks
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
    docker compose exec -T db sh -c 'exec mariadb-dump -uroot -p"$(cat "$MARIADB_ROOT_PASSWORD_FILE")" --single-transaction --routines --triggers "$MARIADB_DATABASE"' \
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
    docker compose exec -T db sh -c 'exec mariadb -uroot -p"$(cat "$MARIADB_ROOT_PASSWORD_FILE")" -e "DROP DATABASE IF EXISTS \`$MARIADB_DATABASE\`; CREATE DATABASE \`$MARIADB_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"'
    case "$db" in *.gz) gunzip -c "$db" ;; *) cat "$db" ;; esac \
        | docker compose exec -T db sh -c 'exec mariadb -uroot -p"$(cat "$MARIADB_ROOT_PASSWORD_FILE")" "$MARIADB_DATABASE"'
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

# Remove the containers, the volumes (database, documents, custom modules), .env and secrets/
[confirm("Remove containers, database, documents and custom modules volumes, .env and secrets/? [y/N]")]
clean: env secrets
    docker compose down --volumes --remove-orphans
    rm -rf .env secrets
