# Run one Mnemosyne sleep/consolidation pass through the local llama.cpp server.
#
# Scheduled instead of letting Mnemosyne's own auto_sleep fire: llama-server
# runs with `-np 1` (mandatory for MTP speculative decode), so a consolidation
# fully serialises behind whatever the agent is doing. A measured pass takes
# ~23s. That is fine once a day in the background and not fine in the middle of
# a Discord reply.
#
# Runs hourly but consolidates at most once a day, because the server is not
# always up - it holds ~20GB of VRAM and is started by hand. A fixed-hour timer
# would regularly find it down, and Mnemosyne would silently fall back to AAAK
# compression rather than an LLM summary, with no signal that the quality
# dropped. Checking hourly takes the first opportunity the server is actually
# up, and the stamp file keeps it to one pass per day.

set -euo pipefail

# --force runs even if today's pass already happened, for invoking by hand.
# --include-recent additionally passes --force to `mnemosyne sleep`, which
# skips the 84h age cutoff and consolidates everything outstanding. Useful for
# a one-off tidy-up; not what the timer should ever do, since consolidating a
# memory minutes after it was stored throws away the detail that made it worth
# storing.
FORCE=0
SLEEP_ARGS=(--all-sessions)
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --include-recent) FORCE=1; SLEEP_ARGS+=(--force) ;;
    -h|--help)
      echo "usage: mnemosyne-consolidate [--force] [--include-recent]"
      echo "  --force           ignore the once-a-day guard"
      echo "  --include-recent  also consolidate memories younger than 84h"
      exit 0 ;;
    *) echo "mnemosyne-consolidate: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

BASE_URL="${MNEMOSYNE_LLM_BASE_URL:-http://localhost:18020/v1}"
HEALTH_URL="${MNEMOSYNE_HEALTH_URL:-http://localhost:18020/health}"
ENV_FILE="${MNEMOSYNE_LLM_ENV_FILE:-/run/secrets/hermes-agent-vllm-env}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mnemosyne"
STAMP="$STATE_DIR/last-consolidation"
TODAY="$(date +%F)"

mkdir -p "$STATE_DIR"

if [ "$FORCE" -eq 0 ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$TODAY" ]; then
  echo "mnemosyne-consolidate: already ran today ($TODAY), nothing to do"
  exit 0
fi

# Skip rather than degrade. The memories stay eligible, so tomorrow's run (or
# the next hour, once the server is back) picks them up with a real summary.
# There is room to wait: a working memory becomes eligible at 84h and is only
# evicted at 168h, so every entry gets roughly three and a half days of
# attempts before anything is lost.
if ! curl -sf --max-time 5 "$HEALTH_URL" >/dev/null 2>&1; then
  echo "mnemosyne-consolidate: no llama-server at $HEALTH_URL, skipping"
  exit 0
fi

# The key. hermes-agent-vllm-env is the existing sops secret, decrypting to a
# literal `VLLM_API_KEY=...` line - the same key that gates this server for
# Hermes. Re-exported under the name Mnemosyne looks for, rather than
# duplicating the secret under a second name.
#
# The systemd unit supplies it through EnvironmentFile, but reading the file
# directly as a fallback is what makes this runnable by hand: an interactive
# shell has no VLLM_API_KEY, and without this the command works from the timer
# and fails everywhere else.
if [ -z "${MNEMOSYNE_LLM_API_KEY:-}" ] && [ -z "${VLLM_API_KEY:-}" ]; then
  if [ -r "$ENV_FILE" ]; then
    VLLM_API_KEY="$(sed -n 's/^VLLM_API_KEY=//p' "$ENV_FILE" | head -n1)"
  fi
fi
if [ -z "${MNEMOSYNE_LLM_API_KEY:-}" ]; then
  if [ -n "${VLLM_API_KEY:-}" ]; then
    export MNEMOSYNE_LLM_API_KEY="$VLLM_API_KEY"
  else
    echo "mnemosyne-consolidate: no API key - not in the environment and not readable from $ENV_FILE" >&2
    exit 1
  fi
fi

export MNEMOSYNE_LLM_BASE_URL="$BASE_URL"

# --all-sessions is load-bearing, not a nicety. A bare `mnemosyne sleep`
# consolidates only the caller's own session, which for this script is
# "default" - so every memory written from a Discord or gateway session would
# be skipped forever and then evicted at the 168h TTL. Verified: without the
# flag this returns no_op while --all-sessions consolidates every session.
echo "mnemosyne-consolidate: consolidating via $BASE_URL"
mnemosyne sleep "${SLEEP_ARGS[@]}"

# Only stamped on success - `set -e` means a failed pass leaves the stamp
# untouched and the next hourly run tries again.
echo "$TODAY" > "$STAMP"
