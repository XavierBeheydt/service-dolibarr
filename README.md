# service-dolibarr

[Dolibarr](https://www.dolibarr.org) ERP & CRM, from the official [`dolibarr/dolibarr`](https://github.com/Dolibarr/dolibarr-docker) image, with MariaDB. Traefik ([`service-traefik`](https://github.com/XavierBeheydt/service-traefik)) serves it over HTTPS on its own host name. The defaults in `.env.example` are for **local testing**. The production values go in `.env` on the VPS.

## Stack

- `web`: Apache and Dolibarr. It sits on the external `proxy` network, and Traefik routes `DOLIBARR_HOST` to it. No port is published on the host.
- `cron`: the same image with `DOLI_CRON=1`. It runs the jobs of the *Scheduled jobs* module every 5 minutes, because the image runs either Apache or cron, never both.
- `db`: MariaDB, reachable only on the internal `backend` network, which has no Internet access.
- Volumes: `db` (database), `documents` (uploaded files, generated PDFs, `install.lock`) and `custom` (external modules).
- `apache/remoteip.*` makes Apache trust Traefik's `X-Forwarded-For`, so the logs and Dolibarr see the real client IP.

At the first start, the `web` container creates the database, the first admin account, the company and the modules from `.env`. This takes about a minute. Dolibarr's `conf.php` is not kept in a volume: the container generates it from the environment each time it is created.

## Recipes

Run `just` to list them. `up`, `down`, `start`, `stop` and `ps` are the common recipes every service provides, so the parent repo can drive all services the same way.

- `just env`: create `.env` from `.env.example` if it is missing
- `just up`: create `.env`, then `docker compose up -d`. Traefik must be running, because it owns the `proxy` network. The command waits until Dolibarr is healthy.
- `just down` / `just start` / `just stop` / `just ps` / `just logs`
- `just backup` / `just restore <stamp>` / `just upgrade`: see the sections below
- `just clean`: after a confirmation, remove the containers, the `db`, `documents` and `custom` volumes, and `.env`. **On the VPS this deletes all the Dolibarr data.**

## Local testing

From the parent repo, start Traefik first:

```bash
just up traefik dolibarr
curl --cacert services/traefik/certs/ca.crt https://dolibarr.docker.localhost/
```

Open <https://dolibarr.docker.localhost> and log in as `admin` / `admin`.

## Production

The DNS record for `DOLIBARR_HOST` must point to the VPS, and Traefik must run with `TLS_CERT_RESOLVER=le`.

```bash
just env
openssl rand -hex 32   # DOLI_INSTANCE_UNIQUE_ID
openssl rand -hex 16   # DOLI_CRON_KEY
openssl rand -hex 24   # DB_PASSWORD, DB_ROOT_PASSWORD, DOLI_ADMIN_PASSWORD
nvim .env              # set DOLIBARR_HOST, the secrets above, DOLI_COMPANY_NAME and DOLI_ENABLE_MODULES
just up
just logs
```

Keep a copy of `.env` somewhere safe, outside the VPS:

- `DOLI_INSTANCE_UNIQUE_ID` encrypts some of the data stored by Dolibarr, so it must never change once Dolibarr is installed. Losing it makes that data unreadable.
- `DOLI_ADMIN_*`, `DOLI_COMPANY_*`, `DOLI_ENABLE_MODULES` and `DOLI_CRON_KEY` are only used at the first start, so editing them later has no effect. Change these settings in Dolibarr instead. Keep `Cron` in `DOLI_ENABLE_MODULES`, or the cron key is not stored and the scheduled jobs are rejected.
- `DB_*` are only used to create the database. Changing a password afterwards also requires changing it in MariaDB.

## Backup and restore

```bash
just backup                    # writes backups/{db,documents,custom}-<stamp>.*
just restore 20261005-142000   # asks for confirmation, then replaces the data with that backup
```

`backup` dumps the database and archives the `documents` and `custom` volumes into `backups/`, which is git-ignored. `just clean` leaves this folder alone. Copy the backups off the VPS: they hold all the data. `restore` recreates the database from `db-<stamp>.sql.gz` (or a plain `.sql`), then replaces each volume whose archive is present. It finishes by recreating the containers. If the backup comes from an older Dolibarr version, the database is migrated at that point.

## Upgrade

```bash
just upgrade
```

`upgrade` runs `backup` first, then pulls the images and recreates the containers without `install.lock`. If the image is newer than the database, the `web` container migrates the database before it locks the installation again. Its own dump goes to `documents/backup-before-upgrade.sql`, and errors go to `documents/migration_error.html`. To move to the next major version, raise `DOLIBARR_VERSION` in `.env` before running it. Dolibarr only supports upgrading one major version at a time.

## Migrating the old instance

The previous instance ran Dolibarr 21 under `/crm`, with its own MariaDB container and its files in host directories (`DOLI_DATA_DOCUMENTS` and `DOLI_DATA_CUSTOM`). On the old server, export everything under one stamp, e.g. `old`. `docker ps` gives the container names:

```bash
docker exec <db container> mariadb-dump -uroot -p'<MYSQL_ROOT_PASSWORD>' --single-transaction <database> | gzip > db-old.sql.gz
tar -C <DOLI_DATA_DOCUMENTS> -czf documents-old.tar.gz .
tar -C <DOLI_DATA_CUSTOM> -czf custom-old.tar.gz .
docker exec <web container> grep instance_unique_id /var/www/html/conf/conf.php
```

Dump only the Dolibarr database, without `--databases`, so the import goes into `DB_NAME`. On the VPS, put the three files in `backups/`. Set `DOLI_INSTANCE_UNIQUE_ID` in `.env` to the old value, so Dolibarr can still read the data it encrypted.

The image migrates the database by only one major version at a time. Start from the version right after the old one, then step up:

```bash
nvim .env            # DOLIBARR_VERSION=22
just up
just restore old     # migrates 21 → 22
nvim .env            # DOLIBARR_VERSION=23
just upgrade         # migrates 22 → 23, and so on up to the target version
```

The restored database brings back the old users, so `DOLI_ADMIN_*` no longer applies. Links to the old `/crm/...` URLs have to be updated to `https://<DOLIBARR_HOST>/...`.
