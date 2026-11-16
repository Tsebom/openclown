# Project instructions

## Config generation and Git identity in the container

The OpenClaw Gateway config and the agent's global instructions are **not
stored in repository files** — they are generated at container start by
`entrypoint.sh` from environment variables (template in `.env.example`,
actual values in `.env`, which is not committed):

- `~/.openclaw/openclaw.json` — Gateway config: auth token, Telegram channel
  (`TELEGRAM_BOT_TOKEN` + allowlist `TELEGRAM_ALLOWED_USER_IDS`), Wormsoft
  model provider (`WORMSOFT_API_KEY`), per-user session isolation.
- `/workspace/AGENTS.md` — global agent instructions with the connected Git
  account identity (`GIT_USER_NAME` / `GIT_USER_EMAIL`), applied to the
  container `git config` as well, so all agent commits are automatically
  attributed to the connected Git account.

- When modifying `entrypoint.sh`, `.env.example`, or `docker-compose.yaml`,
  do not break this mechanism (the env vars must reach the container, and
  the entrypoint must keep generating openclaw.json and the workspace
  AGENTS.md).
- The `.env` file is the single source of truth: edit `.env` and restart
  the container. Runtime changes made in the Control UI are overwritten on
  the next start.
- General git identity rules come from the generated workspace AGENTS.md
  (`/workspace/AGENTS.md` inside the container).
