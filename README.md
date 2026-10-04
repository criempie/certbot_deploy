# Certbot

Certbot запускается в Docker-контейнере и получает сертификаты через Cloudflare DNS-01. Состояние, конфигурация и результаты работы хранятся в каталогах рядом с `docker-compose.yml`.

Контейнерный процесс Certbot запускается под отдельным UID/GID, а не от root. Deploy-hook’и тоже запускаются внутри контейнера от этого пользователя. Для экспорта сертификатов используется отдельный каталог `export/`, который другие сервисы могут подключать только для чтения.

## Требования

- Docker Engine и Docker Compose Plugin.
- DNS-зона, управляемая через Cloudflare.
- Cloudflare API Token с правом редактирования DNS конкретной зоны.

## Создание пользователя и групп

На хосте создайте отдельного системного пользователя `certbot` и группу для файлов экспорта:

```bash
sudo groupadd --system certbot
sudo groupadd --gid 2000 haproxy-certs
sudo useradd --system \
  --gid certbot \
  --groups haproxy-certs \
  --home-dir /var/lib/certbot \
  --shell /sbin/nologin \
  certbot
```

Перед созданием группы проверьте, что GID `2000` свободен:

```bash
getent group 2000
```

Если команда что-то вывела, выберите другой свободный GID и используйте его далее.

Получите числовые UID/GID пользователя и группы:

```bash
id -u certbot
getent group certbot
getent group haproxy-certs
```

В Docker важны именно числовые UID/GID: имена пользователей и групп внутри разных контейнеров могут отличаться. Числа нужно будет указать в `.env`. `certbot` на хосте нужен для владения файлами; сам Certbot запускается в контейнере с теми же числовыми UID/GID.

## Подготовка репозитория

Перейдите в каталог репозитория и создайте файлы конфигурации:

```bash
cp .env.example .env
cp config/cloudflare.ini.example config/cloudflare.ini
```

Заполните `.env`:

```dotenv
UID=1001
GID=1001
EXPORT_GID=2000

ACME_EMAIL=you@example.com
CLOUDFLARE_PROPAGATION_SECONDS=60
```

Замените числа на UID пользователя `certbot`, GID его основной группы и GID группы `haproxy-certs`, полученные командами выше.

Укажите Cloudflare API Token в `config/cloudflare.ini`:

```ini
dns_cloudflare_api_token = YOUR_CLOUDFLARE_API_TOKEN
```

Подготовьте каталоги и права:

```bash
sudo ./scripts/setup-permissions.sh
```

Скрипт создаст `letsencrypt/`, `logs/`, `export/` и `state/`, назначит владельцев и ограничит доступ к Cloudflare-конфигу. Его нужно запускать от root, потому что он меняет владельцев файлов. Если каталог `letsencrypt/` уже содержит данные, скрипт передаст их владельцу, заданному в `.env`.

Сделайте управляющие скрипты исполняемыми:

```bash
chmod +x scripts/*.sh
```

В Compose UID/GID также задаются явно. Поэтому не запускайте Certbot вручную напрямую из образа в обход Compose: используйте скрипты репозитория.

## Первичный выпуск сертификата

Перед выпуском укажите домен или домены:

```bash
./scripts/init.sh example.com www.example.com
```

Первый домен будет основным именем сертификата. Скрипт запускает `certbot certonly` с DNS-01 через Cloudflare. При успешном выпуске Certbot вызывает deploy-hook.

Если нужно автоматически экспортировать сертификат, сначала установите пример hook’а из раздела [Экспорт PEM-файла](#экспорт-pem-файла), затем запускайте `init.sh`.

## Продление через cron

Добавьте задачу в `/etc/cron.d/certbot`, заменив путь на каталог репозитория:

```cron
0 4 * * * root /srv/certbot/scripts/renew.sh >> /var/log/certbot-renew.log 2>&1
```

Запись в `/etc/cron.d/` включает имя пользователя — здесь это `root`. Включите cron, если он ещё не запущен:

```bash
sudo systemctl enable --now crond
```

Здесь root запускает **хостовую команду Docker Compose**. Сам процесс Certbot внутри контейнера работает под UID/GID из `.env`. Доступ к rootful Docker фактически даёт широкие привилегии на хосте, поэтому не добавляйте пользователя в группу `docker`, если не готовы предоставить ему такие права.

`renew.sh` можно запускать ежедневно: Certbot проверит сертификаты и обновит только те, для которых уже подходит срок. Deploy-hook вызывается только при успешном выпуске или обновлении сертификата, а не при каждой проверке.

## Какие скрипты есть

### `scripts/setup-permissions.sh`

Создаёт рабочие каталоги и назначает права на данные Certbot, Cloudflare-конфиг и каталог экспорта.

- Запускается вручную от root при первоначальной настройке.
- Можно запустить повторно после изменения UID/GID.
- Не запускается из cron.

### `scripts/init.sh`

Выпускает сертификат для переданных доменов:

```bash
./scripts/init.sh example.com www.example.com
```

- Запускается вручную для первичного выпуска.
- Передаёт Certbot настройки Cloudflare, email и список доменов.
- Использует тот же deploy-hook, что и продление.

### `scripts/renew.sh`

Запускает проверку и продление сертификатов через `certbot renew`.

- Обычно запускается автоматически через cron.
- Можно запустить вручную для проверки работы продления.
- Если сертификаты не требуется обновлять, пользовательские deploy-hook’и не запускаются.

### `scripts/run-certbot.sh`

Общая хостовая обёртка, которую вызывают `init.sh` и `renew.sh`.

- Удаляет маркер предыдущего запуска.
- Выполняет команду Certbot через `docker compose run`.
- Если контейнерный deploy-hook создал новый маркер, запускает необязательный `hooks/after-renew.sh` на хосте.

Обычно вызывать этот скрипт вручную не нужно.

### `scripts/run-deploy-hooks.sh`

Запускается **внутри контейнера** как deploy-hook Certbot.

- Находит исполняемые `*.sh` в `hooks/deploy.d/`.
- Запускает их по очереди.
- После успешного выполнения создаёт `state/deploy-hook-ran`, который затем использует `run-certbot.sh`.

Вручную запускать его обычно не нужно: его вызывает Certbot при успешном выпуске или обновлении сертификата.

### `hooks/deploy.d/export-pem.sh.example`

Пример пользовательского deploy-hook’а, который создаёт PEM-файл из `fullchain.pem` и `privkey.pem` в каталоге `export/`.

Чтобы включить его:

```bash
cp hooks/deploy.d/export-pem.sh.example hooks/deploy.d/export-pem.sh
chmod +x hooks/deploy.d/export-pem.sh
```

Скрипт с суффиксом `.example` не запускается. Запускаются только файлы `*.sh` с установленным executable-битом.

### `hooks/after-renew.sh` — необязательный хостовый скрипт

Если существует исполняемый `hooks/after-renew.sh`, `run-certbot.sh` запускает его **на хосте** после вызова deploy-hook. Например, там можно вызвать мягкую перезагрузку другого сервиса.

Этот скрипт не поставляется в репозитории: интеграцию и команды в нём определяет администратор. Он запускается от имени пользователя, который вызвал `init.sh` или `renew.sh`; если `renew.sh` запущен из cron от root, хостовый hook тоже запускается от root.

## Deploy-hook’и: как они работают

Поток продления выглядит так:

```text
cron
  └── scripts/renew.sh
      └── scripts/run-certbot.sh
          └── docker compose run certbot renew
              └── scripts/run-deploy-hooks.sh
                  └── hooks/deploy.d/*.sh
          └── hooks/after-renew.sh (необязательно, на хосте)
```

Certbot вызывает deploy-hook после успешного выпуска или обновления сертификата. Скрипты в `hooks/deploy.d/` запускаются внутри контейнера и получают переменные Certbot, в том числе:

- `RENEWED_LINEAGE` — путь к каталогу обновлённого сертификата;
- `RENEWED_DOMAINS` — домены этого сертификата.

Чтобы добавить hook:

1. Создайте файл `hooks/deploy.d/ИМЯ.sh`.
2. Напишите shell-скрипт, используя переменные окружения Certbot.
3. Сделайте его исполняемым:

   ```bash
   chmod +x hooks/deploy.d/ИМЯ.sh
   ```

4. Проверьте работу при следующем выпуске или обновлении сертификата.

Имена файлов удобно начинать с порядкового номера, например `10-export.sh`, `20-notify.sh`: hook’и будут запускаться в порядке обхода шаблона `*.sh`.

### Доступ и ограничения hook’ов

Каталог `hooks/` монтируется в контейнер только для чтения, но скрипты из него **исполняются**. Hook работает от того же UID/GID, что и Certbot, и имеет доступ к подключённым к контейнеру данным:

- `letsencrypt/` — чтение и изменение состояния сертификатов;
- `/cloudflare.ini` — чтение Cloudflare API Token;
- `logs/` — запись логов;
- `export/` — запись экспортируемых файлов;
- `state/` — запись маркера выполнения.

У контейнера нет Docker socket и доступа к Compose-проекту HAProxy. Не устанавливайте недоверенные hook’и: они могут читать Cloudflare Token и приватные ключи, а также изменять доступные Certbot каталоги.

`hooks/after-renew.sh` — отдельный случай: он запускается на хосте, а не в контейнере. Доверяйте ему как обычному хостовому скрипту. Если запускать cron от root, не размещайте в нём непроверенный код.

## Экспорт сертификатов и доступ HAProxy

Пример `export-pem.sh` собирает `fullchain.pem` и `privkey.pem` в файл `/export/<имя-lineage>.pem`. Каталог `export/` принадлежит пользователю Certbot и группе `CERT_EXPORT_GID`; режим `setgid` обеспечивает наследование группы новыми файлами. PEM-файлы создаются с режимом `0640`.

В Compose HAProxy подключите этот каталог **только для чтения** и добавьте ту же числовую группу:

```yaml
services:
  haproxy:
    group_add:
      - "2000"
    volumes:
      - /srv/certbot/export:/etc/haproxy/certs:ro
```

Замените `2000` на значение `CERT_EXPORT_GID`, а путь — на абсолютный путь к каталогу `export/` на хосте. HAProxy не нужно давать доступ к `letsencrypt/live/`.

При использовании экспортируемых PEM-файлов настройте HAProxy на каталог `/etc/haproxy/certs/`. В этом варианте HAProxy не должен пытаться самостоятельно читать исходный каталог Certbot или заново собирать PEM-файлы из `letsencrypt/live/`.

Если после обновления нужен reload HAProxy, поместите его команду в пользовательский `hooks/after-renew.sh`. Это хостовая интеграция: Certbot не знает о HAProxy, а контейнер Certbot не получает доступ к Docker socket.

## Rocky Linux и SELinux

Если SELinux включён и Docker сообщает об отказе доступа к bind mount, добавьте SELinux-метки в `volumes`:

- `:Z` — для каталога, используемого только Certbot;
- `:z` — для общего каталога `export/`, который используют Certbot и HAProxy.

Например, для общего экспорта в Compose Certbot:

```yaml
- ./export:/export:z
```

А в Compose HAProxy:

```yaml
- /srv/certbot/export:/etc/haproxy/certs:ro,z
```

Если репозиторий расположен по другому пути, используйте соответствующий абсолютный путь на хосте.
