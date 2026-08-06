## wiki-js — personal d20 RPG wiki (Wiki.js + Postgres + Nginx + Let's Encrypt)

This repo provides a simple self-hosted setup for a personal RPG wiki using **Wiki.js** with:
- **Postgres 16** for storage
- **Nginx** for HTTP/HTTPS reverse proxy
- **Let's Encrypt (certbot)** for TLS certificates
- Docker Compose for orchestration

---

### What's included
- `docker-compose.yml`: runs `db` (Postgres), `wiki` (Wiki.js), `nginx`, and `certbot`
- `init.sh`: reference outline for bootstrapping Docker + Docker Compose on a Linux (AL2023) host and bringing the stack up — not run automatically anywhere
- `.env.example`: environment variable template
- `nginx/conf.d/default.conf.template`: the live nginx config template, rendered with `envsubst` at container start using `$DOMAIN`
- `letsencrypt/www`: webroot used for ACME HTTP-01 challenges (bind-mounted into both `nginx` and `certbot`)

> `nginx/conf.d/wiki.conf` and `letsencrypt/conf.d/wiki.conf` are old, hardcoded (`murderhobos.wiki`) copies of the config. They are **not** referenced by `docker-compose.yml` or loaded by nginx — only `default.conf.template` is used — and can be treated as stale reference files.

---

### Prerequisites
- A Linux host with Docker-capable permissions (the provided `init.sh` assumes an AWS/Amazon Linux 2023-style environment)
- Domain you control (used by certbot), with DNS pointed at the host
- An email for Let's Encrypt registration

---

### Configuration
Copy the env template:
```bash
cp .env.example .env
```

Populate `.env`:
- `DB_PASS`: Postgres password for the `wiki` user
- `DB_NAME`: currently **unused** — `docker-compose.yml` hardcodes the database name to `wikijs` for both the `db` and `wiki` services regardless of this value
- `DOMAIN`: domain name used for the nginx `server_name`/cert paths and the `certbot -d` flag
- `EMAIL`: email for Let's Encrypt registration

---

### How the pieces fit together
- `nginx` mounts `./nginx/conf.d` to `/etc/nginx/templates` and, on startup, runs:
  ```
  envsubst '$DOMAIN' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf
  ```
  then starts nginx. This means `default.conf.template` is the single source of truth for the nginx config, and `$DOMAIN` is the only variable substituted into it.
- `default.conf.template` defines:
  - port 80: serves `/.well-known/acme-challenge/` from `/var/www/certbot` (for cert issuance/renewal) and redirects everything else to https
  - port 443: terminates TLS using `/etc/letsencrypt/live/${DOMAIN}/{fullchain,privkey}.pem`, proxies to `wiki:3000`, and allows uploads up to `client_max_body_size 15M`
- `certbot` runs `certbot certonly --webroot` against `$DOMAIN`/`$EMAIL` on first start, then loops calling `certbot renew` every 12 hours (`sleep 43200`)
- Certs are persisted in the named `letsencrypt` volume, shared between `nginx` and `certbot`

Because nginx's `default.conf.template` references certs under `/etc/letsencrypt/live/${DOMAIN}/` before they may exist, the very first deployment needs certs issued (e.g. via `init.sh`'s standalone `certbot certonly` step, or an initial run of the `certbot` service) before `nginx` can start successfully.

---

### Local / manual deployment (Docker Compose)
1. Edit `.env`
2. Start the stack:
```bash
docker compose up -d
```

---

### Automated deployment (init script)
`init.sh` is a reference script (not wired into any automation) that:
- Loads variables from `./.env`
- Installs Docker via `dnf`
- Enables/starts Docker and adds `ec2-user` to the `docker` group
- Installs a specific Docker Compose plugin version (`v2.28.1`)
- Clones this repo (if missing)
- Runs `certbot certonly` once for `$DOMAIN`/`$EMAIL` via a one-off `docker compose run`
- Brings the compose stack up with `docker compose up -d`

Run it:
```bash
bash init.sh
```

---

### Ports
- `80:80` exposed for HTTP (ACME challenge + redirect to HTTPS)
- `443:443` exposed for HTTPS

---

### Volumes / persistence
- `postgres_data`: persists Postgres data
- `wiki_data`: persists Wiki.js content (`/wiki` inside the container)
- `letsencrypt`: named volume persisting Let's Encrypt state/certs, shared by `nginx` and `certbot`
- `./nginx/conf.d` → `/etc/nginx/templates` (bind mount, read by nginx at startup)
- `./letsencrypt/www` → `/var/www/certbot` (bind mount, ACME webroot shared by `nginx` and `certbot`)

---

### Common checks
- Containers should be running:
  ```bash
  docker compose ps
  ```
- Certificates should be issued (check `certbot` container logs for success).
- Nginx should be able to reach the `wiki` service on the compose network (`wiki:3000`).
