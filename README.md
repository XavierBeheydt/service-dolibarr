# service-dolibarr

[Dolibarr](https://www.dolibarr.org) ERP & CRM, from the official [`dolibarr/dolibarr`](https://github.com/Dolibarr/dolibarr-docker) image, with MariaDB. Traefik ([`service-traefik`](https://github.com/XavierBeheydt/service-traefik)) serves it over HTTPS on its own host name. The defaults in `.env.example` are for **local testing**. The production values go in `.env` on the VPS.

## Stack

- `web`: Apache and Dolibarr. It sits on the external `proxy` network, and Traefik routes `DOLIBARR_HOST` to it. No port is published on the host.
- `cron`: the same image with `DOLI_CRON=1`. It runs the jobs of the *Scheduled jobs* module every 5 minutes, because the image runs either Apache or cron, never both.
- `db`: MariaDB, reachable only on the internal `backend` network, which has no Internet access.
- Volumes: `db` (database), `documents` (uploaded files, generated PDFs, `install.lock`) and `custom` (external modules).

At the first start, the `web` container creates the database, the first admin account, the company and the modules from `.env`. This takes about a minute. Dolibarr's `conf.php` is not kept in a volume: the container generates it from the environment and the secrets each time it is created.

## Secrets

The passwords and keys are not in `.env`. They are Docker secrets: one file per value in `secrets/` (git-ignored), mounted read-only in `/run/secrets/` and passed to the images through their `*_FILE` variables. They do not show up in `docker inspect` or in the containers' environment.

| File | Used by | Purpose |
| --- | --- | --- |
| `db_password` | db, web, cron | password of `DB_USER` |
| `db_root_password` | db | MariaDB root password, used by `backup` and `restore` |
| `doli_instance_unique_id` | web, cron | key Dolibarr encrypts some data with (e.g. stored passwords) |
| `doli_admin_password` | web | password of the first admin account `DOLI_ADMIN_LOGIN` |
| `doli_cron_key` | web, cron | key the cron container runs the scheduled jobs with |

`just secrets` (run by `just up`) writes a random value into each missing file and keeps the existing ones. To set a value yourself, write it to the file before the first `just up`, without a trailing newline: `printf %s '<value>' > secrets/<name>`. The files are readable by everyone, since MariaDB reads its secrets as the `mysql` user. The `secrets/` folder itself is only accessible to its owner.

## Recipes

Run `just` to list them. `up`, `down`, `start`, `stop` and `ps` are the common recipes every service provides, so the parent repo can drive all services the same way.

- `just env`: create `.env` from `.env.example` if it is missing
- `just secrets`: generate the missing secrets in `secrets/`
- `just up`: create `.env` and the secrets, then `docker compose up -d`. Traefik must be running, because it owns the `proxy` network. The command waits until Dolibarr is healthy.
- `just down` / `just start` / `just stop` / `just ps` / `just logs`
- `just backup` / `just restore <stamp>` / `just upgrade`: see the sections below
- `just clean`: after a confirmation, remove the containers, the `db`, `documents` and `custom` volumes, `.env` and `secrets/`. **On the VPS this deletes all the Dolibarr data.**

## Local testing

From the parent repo, start Traefik first:

```bash
just up traefik dolibarr
curl --cacert services/traefik/certs/ca.crt https://dolibarr.docker.localhost/
```

Open <https://dolibarr.docker.localhost> and log in as `admin`, with the password from `cat services/dolibarr/secrets/doli_admin_password`.

## Production

The DNS record for `DOLIBARR_HOST` must point to the VPS, and Traefik must run with `TLS_CERT_RESOLVER=le`.

```bash
just env
nvim .env              # set DOLIBARR_HOST, DOLI_COMPANY_NAME and DOLI_ENABLE_MODULES
just secrets           # random passwords and keys in secrets/
just up
just logs
cat secrets/doli_admin_password
```

Keep a copy of `.env` and `secrets/` somewhere safe, outside the VPS:

- `doli_instance_unique_id` must never change once Dolibarr is installed. Losing it makes the data Dolibarr encrypted unreadable, even when the database is restored from a backup.
- `DOLI_ADMIN_LOGIN`, `doli_admin_password`, `DOLI_COMPANY_*`, `DOLI_ENABLE_MODULES` and `doli_cron_key` are only used at the first start, so editing them later has no effect. Change these settings in Dolibarr instead. Keep `Cron` in `DOLI_ENABLE_MODULES`, or the cron key is not stored and the scheduled jobs are rejected.
- `DB_*`, `db_password` and `db_root_password` are only used to create the database. Changing a password afterwards also requires changing it in MariaDB.

## Backup and restore

```bash
just backup                    # writes backups/{db,documents,custom}-<stamp>.*
just restore 20261005-142000   # asks for confirmation, then replaces the data with that backup
```

`backup` dumps the database and archives the `documents` and `custom` volumes into `backups/`, which is git-ignored. `just clean` leaves this folder alone. Copy the backups off the VPS: they hold all the data. They do not include `secrets/`, so keep `doli_instance_unique_id` with them. `restore` recreates the database from `db-<stamp>.sql.gz` (or a plain `.sql`), then replaces each volume whose archive is present. It finishes by recreating the containers. If the backup comes from an older Dolibarr version, the database is migrated at that point.

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

Dump only the Dolibarr database, without `--databases`, so the import goes into `DB_NAME`. On the VPS, put the three files in `backups/`. Before the first `just up`, write the old instance ID to the secret (`printf %s '<old value>' > secrets/doli_instance_unique_id`), so Dolibarr can still read the data it encrypted.

The image migrates the database by only one major version at a time. Start from the version right after the old one, then step up:

```bash
nvim .env            # DOLIBARR_VERSION=22
just up
just restore old     # migrates 21 → 22
nvim .env            # DOLIBARR_VERSION=23
just upgrade         # migrates 22 → 23, and so on up to the target version
```

The restored database brings back the old users and the old cron key, so `DOLI_ADMIN_LOGIN`, `doli_admin_password` and `doli_cron_key` no longer apply. Copy the old cron key (*Setup > Modules > Scheduled jobs*) into `secrets/doli_cron_key`, then run `just up` to recreate the cron container. Links to the old `/crm/...` URLs have to be updated to `https://<DOLIBARR_HOST>/...`.
