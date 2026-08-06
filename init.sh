#!/bin/bash
set -e

# Note: This file is basically an outline of what needs to happen on the container. This does not get run anywhere
# And is here for reference.
set -a            # export all variables loaded next
source ./.env
set +a

echo "DOMAIN=$DOMAIN"
echo "EMAIL=$EMAIL"

# --- Install Docker (AL2023 uses dnf) ---
dnf update -y
dnf install -y docker

systemctl enable docker
systemctl start docker

# --- Allow ec2-user to run docker without sudo ---
# (AL2023 default user is ec2-user)
usermod -aG docker ec2-user || true
# Note: group membership takes effect for new logins/boot; container commands later in this script still work as root.

# --- Install Docker Compose plugin (so `docker compose` works) ---
# Some AL2023 images already have it; this is safe to keep.
mkdir -p /usr/local/lib/docker/cli-plugins
COMPOSE_VERSION="v2.28.1"
curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# --- Deploy wiki-js ---
cd /home/ec2-user

if [ ! -d wiki-js ]; then
  git clone https://github.com/coliver/wiki-js.git
fi

cd wiki-js

# Create .env if missing (copy only; you'll still want to ensure it has correct settings)
if [ ! -f .env ]; then
  cp -n .env.example .env || true
fi

# Optional: ensure your certbot/webroot path is wired by the compose stack
docker compose run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  -d "$DOMAIN" \
  --email "$EMAIL" \
  --agree-tos --no-eff-email --force-renewal

docker compose up -d
