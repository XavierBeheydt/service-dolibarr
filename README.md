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
