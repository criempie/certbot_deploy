#!/usr/bin/env bash
set -Eeuo pipefail

# Переходим в каталог проекта, чтобы Docker Compose нашёл конфигурацию.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Не найден .env; создайте его из .env.example" >&2
  exit 1
fi

# Загружаем настройки на хосте, в частности интервал ожидания DNS.
set -a
source ./.env
set +a

# Обёртка запускает Certbot в контейнере и при фактическом обновлении
# может вызвать дополнительный пользовательский скрипт на хосте.
exec "$ROOT/scripts/run-certbot.sh" renew \
  --work-dir /state/work \
  --dns-cloudflare \
  --dns-cloudflare-credentials /cloudflare.ini \
  --dns-cloudflare-propagation-seconds "${CLOUDFLARE_PROPAGATION_SECONDS:-60}" \
  --non-interactive \
  --deploy-hook "/bin/sh /usr/local/bin/run-deploy-hooks.sh"
