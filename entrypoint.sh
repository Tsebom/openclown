#!/bin/sh
# Entrypoint контейнера OpenClaw Gateway.
#
# Что делает перед запуском Gateway:
#   1. Подстраховывает права на стартовый конфиг
#      (в git файл 644, в рантайме желательны 600).
#      Существующий openclaw.json никогда не перезаписывается.
#   2. Собирает команду запуска с фолбэками:
#      штатный entrypoint образа -> openclaw.mjs -> dist/index.js.
#   3. Оборачивает запуск в tini (если он есть в образе — в старых
#      публичных образах его может не быть; безусловный exec
#      /usr/bin/tini тоже даёт 127).
set -e

CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-/home/agent/.openclaw}"
mkdir -p "$CONFIG_DIR"
if [ -f "$CONFIG_DIR/openclaw.json" ]; then
  chmod 600 "$CONFIG_DIR/openclaw.json"
fi

TINI="$(command -v tini || true)"
run() {
  if [ -n "$TINI" ]; then
    exec "$TINI" -s -- "$@"
  fi
  exec "$@"
}

# Штатный entrypoint официального образа. КРИТИЧНО: он ждёт ПОЛНУЮ команду
# в аргументах (в официальном образе её даёт CMD ["node","openclaw.mjs","gateway"]);
# запущенный без аргументов, он завершается с кодом 127.
if [ -f /app/docker-entrypoint.mjs ]; then
  if [ "$#" -eq 0 ]; then
    set -- node /app/openclaw.mjs gateway
  fi
  run node /app/docker-entrypoint.mjs "$@"
fi

# Фолбэки: /app/openclaw.mjs, затем /app/dist/index.js — всегда с подкомандой
# gateway (bare `node ... index.js` без подкоманды — интерактивный TUI,
# в контейнере он спамит "needs an interactive TTY").
if [ "$#" -eq 0 ]; then
  set -- gateway
fi
if [ -f /app/openclaw.mjs ]; then
  run node /app/openclaw.mjs "$@"
fi
run node /app/dist/index.js "$@"
