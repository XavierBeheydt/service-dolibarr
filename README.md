# service-dolibarr

[Dolibarr](https://www.dolibarr.org/) ERP/CRM, from the official `dolibarr/dolibarr` image, with MariaDB, served through Traefik on `dolibarr.<DOMAIN>`.

- **Image**: `dolibarr/dolibarr`, pinned to a major version by `DOLIBARR_VERSION` (24 by default). No custom image, no path prefix.
- **Database**: MariaDB LTS (`MARIADB_VERSION=lts`) in the `db` volume.
- **Networks**: `web` joins the external `proxy` network (owned by `services/traefik`) and the `private` one, shared with `db` only. `db` is never reachable from Traefik and publishes no port.
- **Secrets**: the database user, the database and root passwords, the instance unique ID and the admin password are Docker secrets, one file each in `secrets/` (git-ignored), read through the images' `*_FILE` variables. No secret value appears in `docker inspect`.
- **Not included yet**: the cron container for the scheduled jobs and the real client IP behind Traefik.

## Recipes

Run `just` to list them. `up`, `down`, `start`, `stop` and `ps` are the common recipes every service provides, so the parent repo can drive all services the same way.

- `just env`: create `.env` from `.env.example` if it is missing
- `just secrets`: generate the missing files of `secrets/` with random values (existing ones are kept)
- `just up`: create `.env` and the secrets, then `docker compose up -d`. Traefik must be up first, it owns the `proxy` network.
- `just down` / `just start` / `just stop` / `just ps` / `just logs`
- `just backup`: dump the database and archive the documents into `backups/` (see below)
- `just clean`: after a confirmation, remove the containers, the `db` and `documents` volumes, `.env` and `secrets/`. `backups/` is kept.

## Local testing

```bash
just up traefik dolibarr          # from the parent repo
cat services/dolibarr/secrets/doli_admin_password
```

Open https://dolibarr.docker.localhost and log in as `admin` with that password. `*.docker.localhost` resolves to `127.0.0.1` without any DNS setup, and the certificate comes from `just certs` in `services/traefik` (import its `certs/ca.crt` in your browser, or use `curl --cacert`).

The first start installs Dolibarr, which takes a few minutes: `just logs` shows the progress and `just ps` shows `healthy` once the web container is ready.

## Backup

```bash
just backup
```

Writes `backups/db-<stamp>.sql.gz` (the database, dumped with the application user) and `backups/documents-<stamp>.tar.gz` (the documents) next to the justfile. The stack must be running. `backups/` is git-ignored and survives `just clean`. There is no restore recipe: a new machine starts from a fresh instance.

## Production

The DNS record for `dolibarr.<DOMAIN>` must point to the VPS, and `services/traefik` must run with `TLS_CERT_RESOLVER=le`.

```bash
just env
nvim .env       # set DOMAIN, the same as services/traefik
just up
cat secrets/doli_admin_password
```

Keep `secrets/doli_instance_unique_id` and the database secrets: Dolibarr and MariaDB only read them at the first start, and the instance ID must not change once Dolibarr is installed.
