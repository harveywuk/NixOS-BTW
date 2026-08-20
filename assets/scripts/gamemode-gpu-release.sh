# Release the GPU for a game, called from GameMode's `custom.start` hook.
#
# Two things hold VRAM on this box, and they are released differently:
#
#   lemonade (lemond)        manages its own llama.cpp children - gemma-4-e4b
#                            pinned as the coordinator plus whatever is in the
#                            rotating slot. Unloaded over its REST API; lemond
#                            itself keeps running and will auto-load a model
#                            again on the next request, so nothing needs
#                            restarting afterwards.
#   llama-server-qwen38      a hand-started user unit holding ~20.9 GiB for its
#                            whole run (modules/ai/llama-cpp.nix). Stopped
#                            outright; it never autostarts, so it stays down
#                            until you ask for it.
#
# Measured 2026-08-20: this takes the card from 23111 MiB used to 2221 MiB.
#
# NOT `set -e`. This runs on the path to launching a game, and a game must
# never fail to start because a model server was already down, a secret was
# unreadable, or lemond was mid-restart. Every step is best-effort and the
# script always exits 0. Timeouts are short for the same reason - a hung curl
# here is a hung game launch.
set -uo pipefail

readonly LEMONADE_URL="http://127.0.0.1:13305"
readonly KEY_FILE="/run/secrets/lemonade-env"

# The big hand-started server first: it holds the most and stopping it is
# instant, so the card is freed before the slower REST call runs.
if systemctl --user is-active --quiet llama-server-qwen38; then
  echo "gamemode-gpu-release: stopping llama-server-qwen38"
  systemctl --user stop llama-server-qwen38 || true
fi

# lemond gates every endpoint on the full API key (see modules/ai/lemonade.nix),
# and the secret is mode 0400 owned by mrpickles - readable here because
# GameMode's custom hooks run in the user's gamemoded service, not as root.
if [ -r "$KEY_FILE" ]; then
  key="$(grep -h '^LEMONADE_API_KEY=' "$KEY_FILE" | cut -d= -f2-)"
  if [ -n "$key" ]; then
    echo "gamemode-gpu-release: unloading lemonade models"
    # An empty JSON body means "all models", pinned ones included - a
    # per-model unload would leave the pinned coordinator resident, which is
    # ~4.9 GiB a game would rather have.
    curl -sf --max-time 20 -X POST \
      -H "Authorization: Bearer $key" \
      -H "Content-Type: application/json" \
      -d '{}' "$LEMONADE_URL/api/v1/unload" >/dev/null || true
  fi
else
  echo "gamemode-gpu-release: $KEY_FILE unreadable, skipping lemonade" >&2
fi

exit 0
