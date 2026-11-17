# openclown

## Запуск OpenClaw в Docker

Готовый `docker-compose.yml` + `Dockerfile` запускают OpenClaw Gateway
с веб-панелью по адресу `http://127.0.0.1:18789/`.

Образ собирается из `Dockerfile`: официальный OpenClaw-образ + пользователь
`agent` (**UID/GID 1050**), каталоги состояния под `/home/agent`
(контейнер работает от `agent`, а не от стандартного `node`/1000).
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

# 2. Каталог состояния (на Linux — права на uid 1050, юзер agent, под которым работает контейнер)
mkdir -p data auth-secret
# Linux: sudo chown -R 1050:1050 data auth-secret

# 3. Первый запуск — включить доступ Gateway из браузера (bind=lan + allowedOrigins)
docker compose run --rm --no-deps --entrypoint node openclaw-gateway \
  dist/index.js config set --batch-json \
  '[{"path":"gateway.mode","value":"local"},{"path":"gateway.bind","value":"lan"},{"path":"gateway.controlUi.allowedOrigins","value":["http://localhost:18789","http://127.0.0.1:18789"]}]'

# 4. Поднять контейнер (с первичного `up` compose сам соберёт образ из Dockerfile)
docker compose up -d
```

Откройте `http://127.0.0.1:18789/` и вставьте `OPENCLAW_GATEWAY_TOKEN` из `.env`
в Settings панели.

Альтернатива п. 3 — интерактивный мастер (спросит ключи и сам создаст токен):

```bash
docker compose run --rm --no-deps --entrypoint node openclaw-gateway \
  dist/index.js onboard --mode local --no-install-daemon
```

### Подключение каналов (необязательно)

```bash
docker compose run --rm openclaw-gateway channels add --channel telegram --token "<token>"
docker compose run --rm openclaw-gateway channels login   # WhatsApp по QR
```

### Проверка

```bash
curl -fsS http://127.0.0.1:18789/healthz   # работоспособность
curl -fsS http://127.0.0.1:18789/readyz     # готовность
docker compose logs -f openclaw-gateway
```

### Примечания

- **Доступ из других машин сети:** в `.env` задайте `OPENCLAW_BIND=0.0.0.0`
  и добавьте origin вида `http://<ip-сервера>:18789` в
  `gateway.controlUi.allowedOrigins` (команда `config set` из п. 3). Порт
  защитите файрвоалом (цепочка `DOCKER-USER`).
- **Локальные модели на хосте** (Ollama/LM Studio) из контейнера доступны как
  `http://host.docker.internal:11434` / `http://host.docker.internal:1234`.
- **Обновление:** `docker compose build && docker compose up -d`
  (состояние из `./data` сохранится). Смена базового образа — через
  `OPENCLAW_IMAGE` в `.env` (например, `...:latest-browser` со встроенным
  Chromium) и повторный `docker compose build`.
- **Полная документация:** https://docs.openclaw.ai/ru/install/docker
