# Start, stop or inspect the Chromium instance Hermes' Browser Use backend
# drives over CDP.
#
# Deliberately on demand rather than a systemd service: this browser holds a
# logged-in profile, and something that can act with those cookies should be
# running because you started it, not quietly from boot.
#
# It is a dedicated profile (not the zen-browser daily driver, which is
# Firefox-based and speaks no CDP anyway), so the agent only ever reaches the
# accounts you deliberately sign into here.

set -euo pipefail

PORT="${HERMES_BROWSER_PORT:-9222}"
PROFILE="${HERMES_BROWSER_PROFILE:-${XDG_DATA_HOME:-$HOME/.local/share}/hermes-browser}"
CDP="http://127.0.0.1:$PORT"

alive() { curl -sf --max-time 2 "$CDP/json/version" >/dev/null 2>&1; }

case "${1:---start}" in
  --status)
    if alive; then
      echo "hermes-browser: up on $CDP"
      curl -sf --max-time 2 "$CDP/json/version" | sed -n 's/.*"Browser": "\([^"]*\)".*/  \1/p'
    else
      echo "hermes-browser: not running"
      exit 1
    fi
    ;;
  --stop)
    if ! alive; then echo "hermes-browser: not running"; exit 0; fi
    # Matched on the profile dir, not just the port, so this can never take
    # down an unrelated Chromium that happens to share a debugging port.
    pkill -f -- "--user-data-dir=$PROFILE" || true
    echo "hermes-browser: stopped"
    ;;
  --start)
    if alive; then
      echo "hermes-browser: already up on $CDP"
      exit 0
    fi
    mkdir -p "$PROFILE"
    # setsid + disown so closing the terminal that launched it does not kill
    # the browser mid-task.
    setsid chromium \
      --remote-debugging-port="$PORT" \
      --remote-allow-origins='*' \
      --user-data-dir="$PROFILE" \
      --no-first-run \
      --no-default-browser-check \
      --ozone-platform-hint=auto \
      about:blank >/dev/null 2>&1 &
    disown || true

    for _ in $(seq 1 40); do
      if alive; then
        echo "hermes-browser: up on $CDP (profile: $PROFILE)"
        exit 0
      fi
      sleep 0.25
    done
    echo "hermes-browser: chromium did not open a CDP port on $PORT" >&2
    exit 1
    ;;
  -h|--help)
    echo "usage: hermes-browser [--start|--stop|--status]"
    echo "  the browser Hermes' browser_exec tool drives; log in here once and"
    echo "  the agent inherits those sessions"
    ;;
  *)
    echo "hermes-browser: unknown argument: $1" >&2
    exit 2
    ;;
esac
