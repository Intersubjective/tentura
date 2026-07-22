# Mention e2e (Playwright)

Slack-like `@handle` completion + personal `roomMention` outbox against the local Caddy stack.

Scenarios include shared-prefix multi-match selection via **ArrowDown** and **click/tap**.

## Prerequisites

Same as [local-debug](../../.claude/skills/local-debug/SKILL.md):

1. `docker compose up -d`
2. `./scripts/run-server-local.sh`
3. `./scripts/run-flutter-web-local.sh`
4. `caddy run --config Caddyfile.local`
5. `.env`: `QA_AUTH_ENABLED=true`, `QA_AUTH_TOKEN`, `QA_SIMPLE_LOGIN_MODE=true`

## Run

```bash
cd scripts/e2e_mention
npm install
npm test
# headed: E2E_HEADED=1 npm test
```
