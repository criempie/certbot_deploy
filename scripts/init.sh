#!/usr/bin/env bash
set -Eeuo pipefail

# Находим корень репозитория и переходим в него:
# Compose и .env будут найдены независимо от текущего каталога.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "Сначала создайте .env из .env.example" >&2
  exit 1
fi

# Загружаем настройки, нужные скрипту на хосте.
set -a
source ./.env
set +a

: "${ACME_EMAIL:?Задайте ACME_EMAIL в .env}"

# Для выпуска нужен хотя бы один домен.
if (( $# == 0 )); then
  echo "Использование: $0 domain.example [www.domain.example ...]" >&2
  exit 1
fi

# Формируем аргументы массивом, чтобы домены корректно передавались
# даже при наличии специальных символов в аргументах.
domain_args=()
for domain in "$@"; do
  domain_args+=(-d "$domain")
done

# Передаём команду хостовой обёртке:
# она запустит контейнер Certbot и после deploy-hook при необходимости
# выполнит hooks/after-renew.sh на хосте.
exec "$ROOT/scripts/run-certbot.sh" certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /cloudflare.ini \
  --dns-cloudflare-propagation-seconds "${CLOUDFLARE_PROPAGATION_SECONDS:-60}" \
  --non-interactive \
  --agree-tos \
  --email "$ACME_EMAIL" \
  --deploy-hook "/bin/sh /usr/local/bin/run-deploy-hooks.sh" \
  "${domain_args[@]}"
