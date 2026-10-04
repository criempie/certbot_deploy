#!/usr/bin/env bash
set -Eeuo pipefail

# Определяем корень репозитория относительно расположения скрипта.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Скрипт назначает владельцев файлов и должен запускаться от root.
if [[ $EUID -ne 0 ]]; then
  echo "Запустите скрипт от root: sudo $0" >&2
  exit 1
fi

# CERTBOT_UID/CERTBOT_GID должны быть заданы в .env простыми shell-совместимыми строками.
if [[ ! -f .env ]]; then
  echo "Сначала создайте .env из .env.example" >&2
  exit 1
fi

set -a
source ./.env
set +a

: "${CERTBOT_UID:?Не задан CERTBOT_UID}"
: "${CERTBOT_GID:?Не задан CERTBOT_GID}"
: "${EXPORT_GID:?Не задан EXPORT_GID}"

# Создаём каталоги конфигурации и deploy-hook'ов.
mkdir -p config hooks/deploy.d

# Если приватный Cloudflare-конфиг ещё не создан, копируем шаблон.
if [[ ! -f config/cloudflare.ini ]]; then
  cp config/cloudflare.ini.example config/cloudflare.ini
fi

# Каталоги состояния Certbot доступны ему на запись.
install -d -o "$CERTBOT_UID" -g "$CERTBOT_GID" -m 0750 \
  letsencrypt logs state

chown -R "$CERTBOT_UID:$CERTBOT_GID" letsencrypt logs state

# Родительский export доступен для просмотра и прохода, но не для записи.
# Владелец root не даёт Certbot создавать в нём произвольные каталоги.
mkdir -p export
chown root:root export
chmod 0755 export

# Отдельный каталог для PEM-файлов HAProxy.
# Certbot — владелец и может записывать; группа HAProxy может читать и
# проходить в каталог; остальные пользователи доступа не имеют.
mkdir -p export/haproxy
chown -R "$CERTBOT_UID:$EXPORT_GID" export/haproxy

# setgid на каталогах обеспечивает наследование группы EXPORT_GID.
find export/haproxy -type d -exec chmod 2750 {} +

# PEM-файлы доступны владельцу для записи и группе для чтения.
find export/haproxy -type f -exec chmod 0640 {} +

# Cloudflare API Token доступен только пользователю Certbot.
chown "$CERTBOT_UID:$CERTBOT_GID" config/cloudflare.ini
chmod 0600 config/cloudflare.ini

echo "Каталоги и права подготовлены."
echo "Проверьте Cloudflare API Token в config/cloudflare.ini."
