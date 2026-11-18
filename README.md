# openclown

## Запуск OpenClaw в Docker

Готовый `docker-compose.yml` + `Dockerfile` запускают OpenClaw Gateway
с веб-панелью по адресу `http://127.0.0.1:18789/`.

Образ собирается из `Dockerfile`: официальный OpenClaw-образ + пользователь
`agent` (**UID/GID 1050**), каталоги состояния под `/home/agent`
(контейнер работает от `agent`, а не от стандартного `node`/1000).
Стартовый конфиг Gateway — `data/openclaw.json` в репозитории
(минимум для первого старта: `mode=local`, `bind=lan`); он отслеживается
в git, Gateway сам дособавляет в него остальные настройки при запуске
(такие изменения видны в `git status`).
Базовый образ задаётся в `.env` через `OPENCLAW_IMAGE`
(по умолчанию `ghcr.io/openclaw/openclaw:latest`).

### Требования

- Docker Engine (или Docker Desktop) + Docker Compose v2
- При сборке/работе: ≥ 2 GB RAM

### Запуск

```bash
# 1. Секреты: токен Gateway и ключ(и) провайдера моделей
cp .env.example .env
# отредактируйте .env: OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32) и ключ провайдера

# 2. Каталог состояния (уже в репозитории; на Linux — права на uid 1050, юзер agent)
mkdir -p data auth-secret
# Linux: sudo chown -R 1050:1050 data auth-secret

# 3. Запуск. Стартовый конфиг Gateway (data/openclaw.json из репозитория:
# gateway.mode=local, gateway.bind=lan) уже в смонтированном томе;
# compose сам соберёт образ из Dockerfile.
docker compose up -d
```

Откройте `http://127.0.0.1:18789/` **с самой машины Gateway** и вставьте
`OPENCLAW_GATEWAY_TOKEN` из `.env` в Settings — это всё, чат доступен
(подтверждение устройства для loopback-соединений не требуется).

Альтернатива — интерактивный мастер первоначальной настройки (спросит ключи
и сам создаст токен):

```bash
docker compose run --rm --no-deps --entrypoint node openclaw-gateway \
  dist/index.js onboard --mode local --no-install-daemon
```

### Подключение каналов (необязательно)

Одноразовые CLI-команды выполняются с `--entrypoint node` и явным путём
к CLI (обход entrypoint'а-обёртки; `docker compose run ... channels add`
без этого не находит бинарник `channels`):

```bash
docker compose run --rm --no-deps --entrypoint node openclaw-gateway \
  dist/index.js channels add --channel telegram --token "<token>"
docker compose run --rm --no-deps --entrypoint node openclaw-gateway \
  dist/index.js channels login   # WhatsApp по QR
```

### Проверка

```bash
curl -fsS http://127.0.0.1:18789/healthz   # работоспособность
curl -fsS http://127.0.0.1:18789/readyz     # готовность
docker compose logs -f openclaw-gateway
```

### Доступ из других машин сети (необязательно)

1. В `.env` задайте `OPENCLAW_BIND=0.0.0.0` (порт 18789 защитите файрвоалом,
   цепочка `DOCKER-USER`).
2. Сетевые (не loopback) браузеры требуют **разового** подтверждения
   устройства: страница панели покажет request ID — одобрение выполняется
   на хосте, **внутри работающего контейнера**:

```bash
docker compose exec openclaw-gateway \
  openclaw devices approve <requestId>
```

   Важно: не используйте здесь `docker compose run ... devices approve` —
   это поднимает *отдельный* контейнер, и пока Gateway запущен, CLI из него
   не может изменить состояние (ошибка «cannot verify Gateway ownership ...
   Run this command inside the Gateway container»). `exec` запускает команду
   в том же контейнере, где работает Gateway, и одобрение проходит через
   него. Если запрос истёк (у pending-запросов есть TTL) — просто обновите
   страницу панели и возьмите новый ID.

После одобрения браузер запоминается и повторных подтверждений не будет
(сброс: `docker compose exec openclaw-gateway openclaw devices revoke
--device <id> --role <role>`).

Если браузер находится **на самой машине Gateway**, проще не одобрять ничего:
открывайте `http://127.0.0.1:18789/`, а не сетевой адрес — loopback-соединения
авто-апрувят pairing, и экран «Approve this browser» не показывается.

### Примечания

- **Модели (провайдер Wormsoft):** стартовый конфиг `data/openclaw.json`
  уже подключает провайдера `wormsoft` со всеми системными алиасами
  (MyCode — кастомный алиас, Low/Medium/High Agent, Low/Medium/High Code,
  Low/Medium/High Vision) и моделью по умолчанию
  `wormsoft/wormsoft/code/medium` (работает на любом тарифе; High-модели
  требуют тариф simple и выше — документация:
  https://ai.wormsoft.ru/docs/connect/openclaw,
  https://ai.wormsoft.ru/docs/llm/system-aliases).
  Ключ не хранится в конфиге — берётся из переменной окружения
  `WORMSOFT_API_KEY` (задаётся в `.env`, не опционально: без ключа
  агент не сможет отвечать).

- **Локальные модели на хосте** (Ollama/LM Studio) из контейнера доступны как
  `http://host.docker.internal:11434` / `http://host.docker.internal:1234`.
- **Обновление:** `docker compose build && docker compose up -d`
  (состояние из `./data` сохранится). Смена базового образа — через
  `OPENCLAW_IMAGE` в `.env` (например, `...:latest-browser` со встроенным
  Chromium) и повторный `docker compose build`.
- **Полная документация:** https://docs.openclaw.ai/ru/install/docker
