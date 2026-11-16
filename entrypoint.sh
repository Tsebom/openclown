#!/bin/bash
set -e

# =============================================================================
# OpenClaw container entrypoint
#
# All secrets and access lists live in .env (see .env.example) and the
# entrypoint turns them into the live Gateway config on every container start:
#
#   1. ~/.openclaw/openclaw.json  - Gateway config: auth token, Telegram
#      channel (bot token + allowlist of numeric user IDs), optional model
#      provider, per-user session isolation.
#   2. ~/.ssh                     - SSH key bootstrap (bind-mounted host dir).
#
# The .env file is the single source of truth: edit .env, restart the
# container. Runtime changes made in the Control UI are overwritten on the
# next start.
# =============================================================================

# --- Fail fast on missing required environment (see .env.example) ----------
# A broken .env must abort here with a clear message instead of failing
# later as an opaque Gateway config-validation error.
missing=""
for var in TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_USER_IDS; do
    if [ -z "${!var}" ]; then
        missing="$missing $var"
    fi
done
if [ -n "$missing" ]; then
    echo "ERROR: missing required environment variables:$missing" >&2
    echo "       Copy .env.example to .env and fill in the values (see README.md)." >&2
    exit 1
fi

# --- Gateway / Control UI auth token ----------------------------------------
# Used for browser access to the Control UI and for the Gateway API.
# If left empty, a random token is generated and printed in the logs
# (docker logs openclaw-standalone).
if [ -z "${OPENCLAW_GATEWAY_TOKEN}" ]; then
    OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)"
    export OPENCLAW_GATEWAY_TOKEN
    echo "WARN: OPENCLAW_GATEWAY_TOKEN is not set - generated a random token."
    echo "Gateway/Control UI token: ${OPENCLAW_GATEWAY_TOKEN}"
fi

# --- Build the Telegram allowFrom JSON array --------------------------------
# TELEGRAM_ALLOWED_USER_IDS is a comma-separated list of NUMERIC Telegram
# user IDs (the only users allowed to DM the bot; everyone else is ignored).
# "telegram:" / "tg:" prefixes are accepted and stripped.
ALLOW_FROM="["
first=1
for raw in ${TELEGRAM_ALLOWED_USER_IDS//,/ }; do
    id="${raw//[[:space:]]/}"
    id="${id#telegram:}"
    id="${id#tg:}"
    if [ -z "$id" ]; then
        continue
    fi
    case "$id" in
        *[!0-9]*)
            echo "ERROR: TELEGRAM_ALLOWED_USER_IDS must contain numeric Telegram user IDs, got '$id'." >&2
            echo "       Find your user ID: DM the bot (it reports it in the pairing reply)," >&2
            echo "       or curl 'https://api.telegram.org/bot<TOKEN>/getUpdates' and read from.id." >&2
            exit 1
            ;;
    esac
    if [ "$first" -eq 0 ]; then
        ALLOW_FROM="${ALLOW_FROM}, "
    fi
    ALLOW_FROM="${ALLOW_FROM}\"${id}\""
    first=0
done
ALLOW_FROM="${ALLOW_FROM}]"
if [ "$ALLOW_FROM" = "[]" ]; then
    echo "ERROR: TELEGRAM_ALLOWED_USER_IDS is empty. Add at least one numeric Telegram user ID." >&2
    exit 1
fi

# --- Build the Control UI allowedOrigins list --------------------------------
# The default origins cover a dashboard opened on the Gateway host itself.
# For browser access from other machines, add the exact URLs you open
# (comma-separated) via OPENCLAW_CONTROL_UI_ORIGINS in .env.
ORIGINS_LIST='"http://localhost:18789", "http://127.0.0.1:18789"'
if [ -n "${OPENCLAW_CONTROL_UI_ORIGINS}" ]; then
    for raw in ${OPENCLAW_CONTROL_UI_ORIGINS//,/ }; do
        url="${raw//[[:space:]]/}"
        if [ -n "$url" ]; then
            ORIGINS_LIST="${ORIGINS_LIST}, \"${url}\""
        fi
    done
fi

# --- Model provider ------------------------------------------------------------
# The model provider is OPTIONAL and pluggable: it is registered in the
# generated config below, so switching providers in the future only requires
# registering another one here (models.providers) and setting OPENCLAW_MODEL.
#
# Currently the Wormsoft (OpenAI-compatible) endpoint is registered when
# WORMSOFT_API_KEY is set in .env.
MODEL_PRIMARY="${OPENCLAW_MODEL:-}"
MODEL_CLAUSE=""
MODELS_SECTION=""
if [ -n "${WORMSOFT_API_KEY}" ]; then
    [ -n "$MODEL_PRIMARY" ] || MODEL_PRIMARY="wormsoft/code/medium"
    MODEL_CLAUSE=", \"model\": { \"primary\": \"${MODEL_PRIMARY}\" }"
    MODELS_SECTION=",
  \"models\": {
    \"providers\": {
      \"wormsoft\": {
        \"name\": \"Wormsoft\",
        \"baseUrl\": \"https://ai.wormsoft.ru/api/gpt\",
        \"apiKey\": \"\${WORMSOFT_API_KEY}\",
        \"api\": \"openai-completions\",
        \"models\": [
          { \"id\": \"mine/onlycode\", \"name\": \"MyCode\" },
          { \"id\": \"agent/low\", \"name\": \"LowAgent\" },
          { \"id\": \"agent/medium\", \"name\": \"MediumAgent\" },
          { \"id\": \"agent/high\", \"name\": \"HighAgent\" },
          { \"id\": \"code/low\", \"name\": \"LowCode\" },
          { \"id\": \"code/medium\", \"name\": \"MediumCode\" },
          { \"id\": \"code/high\", \"name\": \"HighCode\" },
          { \"id\": \"vision/low\", \"name\": \"LowVision\" },
          { \"id\": \"vision/medium\", \"name\": \"MediumVision\" },
          { \"id\": \"codevision/high\", \"name\": \"HighVision\" }
        ]
      }
    }
  }"
fi
if [ -z "$MODEL_PRIMARY" ] && [ -z "${WORMSOFT_API_KEY}" ]; then
    echo "WARN: no model provider configured - set WORMSOFT_API_KEY in .env (or register"
    echo "       another provider in entrypoint.sh) and optionally OPENCLAW_MODEL."
fi

# --- Generate the Gateway config ---------------------------------------------
# ~/.openclaw/openclaw.json is regenerated on every start from the
# environment (the .env file is the source of truth).
# ${WORMSOFT_API_KEY} and ${TELEGRAM_BOT_TOKEN} are kept as OpenClaw
# environment references (resolved by OpenClaw at runtime, never baked in).
STATE_DIR="${HOME}/.openclaw"
mkdir -p "$STATE_DIR"
if ! { cat > "${STATE_DIR}/openclaw.json" <<EOF
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789,
    "controlUi": {
      "allowedOrigins": [${ORIGINS_LIST}]
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/workspace"${MODEL_CLAUSE}
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "\${TELEGRAM_BOT_TOKEN}",
      "dmPolicy": "allowlist",
      "allowFrom": ${ALLOW_FROM},
      "groupPolicy": "disabled"
    }
  },
  "session": {
    "dmScope": "per-channel-peer"
  }
${MODELS_SECTION}
}
EOF
}; then
    echo "WARN: could not write ${STATE_DIR}/openclaw.json - state volume is not writable by UID 1050."
    echo "Fix on the host: sudo chown -R 1050:1050 <openclaw-state volume path>, then restart."
fi

# --- SSH bootstrap ---------------------------------------------------------------
# Ensure the directory and key exist.
# /home/agent/.ssh is a bind mount (.openclaw/ssh on the host). If the host
# volume is not owned by the container user (UID 1050), chmod/keygen fail -
# warn and continue instead of crash-looping the container.
mkdir -p /home/agent/.ssh 2>/dev/null || true
if ! chmod 700 /home/agent/.ssh 2>/dev/null; then
    echo "WARN: cannot chmod /home/agent/.ssh - host volume is not owned by UID 1050."
    echo "Fix on the host: sudo chown -R 1050:1050 .openclaw/ssh"
fi

if [ ! -f "/home/agent/.ssh/id_ed25519" ]; then
    # Generate the key without a passphrase
    if ! ssh-keygen -t ed25519 -f /home/agent/.ssh/id_ed25519 -N ""; then
        echo "WARN: could not generate SSH key - .openclaw/ssh is not writable by UID 1050."
        echo "Fix on the host: sudo chown -R 1050:1050 .openclaw/ssh"
    fi
fi

# Execute the original command passed as arguments
exec "$@"
