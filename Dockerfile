# OpenClaw Gateway, работающий от пользователя `agent` (UID 1050).
#
# Базовый образ — официальный (документация: https://docs.openclaw.ai/ru/install/docker).
# Официальный образ запускается от `node` (UID 1000); здесь создаём своего
# пользователя `agent` (UID 1050), переносим каталоги состояния в /home/agent
# и переключаем контейнер на него.
#
# Сборка:
#   docker build -t openclaw:agent-1050 .
#
# Другой базовый образ (например, с Chromium):
#   docker build --build-arg OPENCLAW_BASE=ghcr.io/openclaw/openclaw:latest-browser \
#     -t openclaw:agent-1050 .

ARG OPENCLAW_BASE=ghcr.io/openclaw/openclaw:latest
FROM ${OPENCLAW_BASE}

# Официальный образ работает от non-root `node` (uid 1000), поэтому
# для создания пользователя нужен временный переход на root.
USER root

# Пользователь agent: UID 1050 / GID 1050 + каталоги состояния
RUN groupadd --gid 1050 agent \
 && useradd --uid 1050 --gid 1050 --create-home --shell /usr/sbin/nologin agent \
 && mkdir -p /home/agent/.openclaw/workspace /home/agent/.config/openclaw \
 && chown -R 1050:1050 /home/agent

# Явные пути состояния (см. docs, «Хранение и постоянство данных»):
# config + workspace + каталог ключа профилей OAuth — под /home/agent
ENV HOME=/home/agent \
    OPENCLAW_CONFIG_DIR=/home/agent/.openclaw \
    OPENCLAW_WORKSPACE_DIR=/home/agent/.openclaw/workspace \
    OPENCLAW_AUTH_PROFILE_SECRET_DIR=/home/agent/.config/openclaw

# Вступительный скрипт: при первом запуске (если openclaw.json ещё нет)
# создаёт минимальную рабочую конфигурацию Gateway (mode=local, bind=lan),
# чтобы `docker compose up -d` работало без ручного `config set`.
# Существующий openclaw.json никогда не перезаписывается.
RUN printf '%s\n' \
      '#!/bin/sh' \
      'set -e' \
      'CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-/home/agent/.openclaw}"' \
      'if [ ! -f "$CONFIG_DIR/openclaw.json" ]; then' \
      '  cat > "$CONFIG_DIR/openclaw.json" <<EOF' \
      '{' \
      '  gateway: {' \
      '    mode: "local",' \
      '    bind: "lan",' \
      '  },' \
      '}' \
      'EOF' \
      '  chmod 600 "$CONFIG_DIR/openclaw.json"' \
      'fi' \
      'if [ "$#" -eq 0 ]; then' \
      '  set -- node /app/dist/index.js' \
      'fi' \
      'if [ -x /usr/bin/tini ]; then' \
      '  exec /usr/bin/tini -- "$@"' \
      'fi' \
      'exec "$@"' \
      > /usr/local/bin/openclaw-entrypoint.sh \
 && chmod 755 /usr/local/bin/openclaw-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/openclaw-entrypoint.sh"]

# Gateway запускается от agent (UID 1050), а не от node (UID 1000)
USER agent
