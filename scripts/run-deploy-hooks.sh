#!/bin/sh
set -eu

# hooks смонтирован в контейнер только для чтения.
# Пользовательские скрипты должны быть shell-скриптами с расширением .sh.
hook_dir=/hooks/deploy.d

# Перебираем deploy-hook'и. Если файлов нет, glob останется строкой
# с шаблоном; проверка -f пропустит её.
for hook in "$hook_dir"/*.sh; do
    [ -f "$hook" ] || continue

    # Не пытаемся запускать скрипт без executable-бита:
    # выдаём понятную ошибку вместо неочевидного сбоя.
    if [ ! -x "$hook" ]; then
        echo "Deploy-hook не исполняемый: $hook" >&2
        exit 1
    fi

    echo "Запуск deploy-hook: $hook"

    # Скрипт наследует переменные Certbot, включая RENEWED_LINEAGE
    # и RENEWED_DOMAINS, и запускается от пользователя Certbot.
    "$hook"
done

# Маркер сообщает хостовой обёртке, что Certbot вызвал deploy-hook.
# Создаём его только после успешного завершения всех пользовательских скриптов.
touch /state/deploy-hook-ran
