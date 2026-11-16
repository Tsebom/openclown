# OpenClaw Standalone Deployment

This repository provides a production-ready Docker deployment for OpenClaw.
One Gateway container serves:

- **Telegram** — several allowed users chat with the agent by DM
  (allowlist, token from `.env`);
- **Browser** — the OpenClaw Control UI (dashboard) on the published port.

The agent runs with the Wormsoft (OpenAI-compatible) model provider and works
in `/workspace`.

## 🚀 Quick Start

1. **Clone the repository** (or navigate to the folder).
2. **Configure Environment Variables**:
   ```bash
   cp .env.example .env
   # Edit .env with your keys, the bot token, and allowed user IDs
   nano .env
   ```
3. **Fix host permissions** (one-time, see [Permissions and SSH Setup](#-permissions-and-ssh-setup)).
4. **Launch the Container**:
   ```bash
   docker compose up -d
   ```
5. **Access the Control UI**:
   Open your browser and go to `http://localhost:18789` (or the port you
   specified in `.env`), and paste `OPENCLAW_GATEWAY_TOKEN` into **Settings**.
6. **Chat via Telegram**: DM your bot. Only users from
   `TELEGRAM_ALLOWED_USER_IDS` get a reply; everyone else is ignored.

## ⚙️ Configuration

All settings come from `.env`. **Edit `.env` and restart the container**
(`docker compose up -d`); the entrypoint regenerates the Gateway config on
every start, so runtime changes made in the Control UI are overwritten.

### Server Settings

- `OPENCLAW_PORT`: the host port where the Gateway / Control UI is published
  (default: `18789`). The container always listens internally on port 18789.
- `OPENCLAW_GATEWAY_TOKEN`: the auth token for the Web UI and the Gateway API
  (paste it into dashboard Settings). If not set, a random one is generated
  and visible in `docker logs openclaw-standalone`.
- `OPENCLAW_MODEL`: the primary agent model (default: `wormsoft/code/medium`).
- `OPENCLAW_CONTROL_UI_ORIGINS`: optional extra allowed origins
  (comma-separated URLs) for opening the dashboard from other machines, e.g.
  `https://claw.example.com,http://192.168.1.10:18789`.

### Telegram

- `TELEGRAM_BOT_TOKEN`: the bot token from [@BotFather](https://t.me/BotFather)
  (create a bot with `/newbot`).
- `TELEGRAM_ALLOWED_USER_IDS`: **who may DM the bot** — a comma-separated
  list of *numeric* Telegram user IDs. Access is an allowlist
  (`dmPolicy: allowlist`): any other account, even if it finds the bot, is
  ignored. Group chats are disabled by default.

**Finding your numeric user ID** (not a phone number, not a username):

- DM your bot — the bot replies with `Your Telegram user id` in the pairing flow;
- or the official Bot API:
  ```bash
  curl "https://api.telegram.org/bot<TOKEN>/getUpdates"
  ```
  and read `from.id` of your message;
- or (less private) `@userinfobot` / `@getidsbot`.

Each allowed user gets an isolated session (`session.dmScope:
per-channel-peer`), so several users can chat with the same bot without
sharing conversations.

### Model Provider

The agent uses the Wormsoft OpenAI-compatible endpoint
(`https://ai.wormsoft.ru/api/gpt`) with the `WORMSOFT_API_KEY` from `.env`.
The full model catalog is registered in the generated config; switch the
primary model via `OPENCLAW_MODEL` (e.g. `wormsoft/agent/medium`,
`wormsoft/code/high`, `wormsoft/vision/medium`).

## 🔐 Permissions and SSH Setup

To allow the agent to automatically generate and manage SSH keys, and to
keep the state/workspace volumes writable, the file permissions on your host
machine must match the internal user of the container (UID: 1050, GID: 1050).

**1. Create a corresponding user on your host (one-time setup):**
```bash
sudo groupadd -g 1050 agent
sudo useradd -u 1050 -g agent -m agent
```

**2. Set the ownership for the project folder:**
```bash
sudo chown -R agent:agent .openclaw
```

**3. Verify the setup:**
```bash
# List the SSH folder contents
sudo -u agent ls -l .openclaw/ssh

# View the public key
sudo -u agent cat .openclaw/ssh/id_ed25519.pub
```

The named Docker volumes (`openclaw-state`, `openclaw-workspace`) are
initialized with the correct ownership on first start, because the mount
points are pre-created in the image with `agent:agent` ownership. If you
mount host directories instead, give them the same ownership
(`sudo chown -R 1050:1050 <path>`).

## 🛠 Maintenance

**Viewing Logs:**
```bash
docker logs -f openclaw-standalone
```

**Checking Health:**
The container includes a healthcheck that pings the auth-free `/healthz`
endpoint. Check the status with:
```bash
docker ps
```

**Updating:**
```bash
docker compose build
docker compose up -d
```
On image upgrades the entrypoint runs the usual startup repair automatically
(one Gateway per state volume — stop the old container before starting the
replacement, which `docker compose up -d` does for you).

## 🔒 Security Notes

- The Gateway binds to all interfaces (`bind: lan`) so the host port mapping
  works; unauthenticated access to the Control UI/API is blocked by the
  token. If you expose the port on a public host, keep the token strong and
  consider a firewall / reverse proxy in front (and see the OpenClaw docs on
  network-exposure hardening and the Docker `DOCKER-USER` firewall chain).
- For remote browser access, add the URL you actually open to
  `OPENCLAW_CONTROL_UI_ORIGINS`.
- Telegram groups are disabled and DMs are allowlisted: only the user IDs in
  `TELEGRAM_ALLOWED_USER_IDS` can talk to the agent.

## Related

- OpenClaw docs: https://docs.openclaw.ai
- Telegram channel: https://docs.openclaw.ai/channels/telegram
- Docker install: https://docs.openclaw.ai/install/docker
