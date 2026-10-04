#!/usr/bin/env bash
set -u

# Определяем каталог проекта и выполняем Compose из него.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Удаляем возможный маркер от предыдущего запуска:
# он должен отражать только результат текущей команды.
mkdir -p state
rm -f state/deploy-hook-ran

# Запускаем Certbot и сохраняем код возврата, чтобы ниже обработать
# маркер и возможный хостовый hook даже при ошибке команды.
docker compose run --rm certbot "$@"
certbot_status=$?

post_status=0

# Маркер создаёт run-deploy-hooks.sh после выполнения deploy-hook'ов.
# Это означает, что сертификат был успешно выпущен или обновлён.
if [[ -f state/deploy-hook-ran ]]; then
  rm -f state/deploy-hook-ran

  # Этот скрипт исполняется на хосте, от имени пользователя,
  # запустившего run-certbot.sh. Он не входит в базовую конфигурацию.
  if [[ -x hooks/after-renew.sh ]]; then
    hooks/after-renew.sh || post_status=$?
  fi
fi

# Если Certbot завершился ошибкой, возвращаем именно его код ошибки.
if (( certbot_status != 0 )); then
  exit "$certbot_status"
fi

# Иначе возвращаем код ошибки хостового hook'а, если он был запущен.
exit "$post_status"
