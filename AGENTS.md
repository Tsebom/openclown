# Project instructions

## Config generation in the container

The OpenClaw Gateway config is **not stored in repository files** — it is
generated at container start by `entrypoint.sh` from environment variables
(template in `.env.example`, actual values in `.env`, which is not
committed):

- `~/.openclaw/openclaw.json` — Gateway config: auth token, Telegram channel
  (`TELEGRAM_BOT_TOKEN` + allowlist `TELEGRAM_ALLOWED_USER_IDS`), Wormsoft
  model provider (`WORMSOFT_API_KEY`), per-user session isolation.

- When modifying `entrypoint.sh`, `.env.example`, or `docker-compose.yaml`,
  do not break this mechanism (the env vars must reach the container, and
  the entrypoint must keep generating openclaw.json).
- The `.env` file is the single source of truth: edit `.env` and restart
  the container. Runtime changes made in the Control UI are overwritten on
  the next start.
