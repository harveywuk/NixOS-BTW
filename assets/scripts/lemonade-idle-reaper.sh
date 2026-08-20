# Unload lemonade models that have gone idle, so the day-to-day resting state
# is the ~4.9 GiB coordinator rather than the ~21 GiB full stack.
#
# Only UNPINNED models are touched. gemma-4-e4b is pinned (ai/lemonade.nix), so
# it stays resident and keeps answering instantly; the rotating slot - normally
# muse-glimmer-30b at ~16 GiB - is what gets reclaimed.
#
# Nothing needs to restart it. lemond auto-loads a model on the next request
# that names it ("Auto-loading model: ..."), so a delegate_task from the
# coordinator, or any Hermes bot turn, brings Muse back by itself. The only
# cost is a reload on that first call - measured at 6.1s with the weights
# still in page cache, longer after a reboot or once something else has
# evicted them.
#
# This exists because lemond's OWN idle eviction is not reachable: the binary
# carries `evict_idle_timeout` and `downsize_idle_timeout`, but /internal/set
# rejects both with "Unknown config key" - they are internal constants, not
# configuration. The pressure-based `auto_evict` path IS settable and is
# unusable here for separate reasons (see ai/lemonade.nix). So idleness is
# tracked from outside instead, which turns out to be easy:
#
#   GET /api/v1/health -> all_models_loaded[].last_use
#
# last_use is MILLISECONDS SINCE BOOT on the same clock as /proc/uptime -
# verified 2026-08-20 by routing one request and watching it land within 7 ms
# of the uptime reading. It only advances for requests routed THROUGH lemond;
# talking to a llama-server's own port directly leaves it untouched, which is
# correct for this purpose but worth knowing when testing by hand.
set -uo pipefail

readonly URL="http://127.0.0.1:13305"
readonly KEY_FILE="/run/secrets/lemonade-env"
IDLE_SECONDS="${LEMONADE_IDLE_SECONDS:-1800}"

if [ ! -r "$KEY_FILE" ]; then
  echo "lemonade-idle-reaper: $KEY_FILE unreadable" >&2
  exit 0
fi
key="$(grep -h '^LEMONADE_API_KEY=' "$KEY_FILE" | cut -d= -f2-)"
[ -n "$key" ] || exit 0

health="$(curl -sf --max-time 20 -H "Authorization: Bearer $key" "$URL/api/v1/health")" || {
  echo "lemonade-idle-reaper: lemond not answering, nothing to do"
  exit 0
}

# Emits one model name per line for each unpinned, not-currently-working model
# whose idle time exceeds the threshold. is_busy/is_streaming are checked so a
# model is never pulled out from under an in-flight turn or an open stream.
mapfile -t victims < <(
  printf '%s' "$health" | IDLE_SECONDS="$IDLE_SECONDS" python3 -c '
import json, os, sys

idle_limit = float(os.environ["IDLE_SECONDS"]) * 1000.0
with open("/proc/uptime") as f:
    uptime_ms = float(f.read().split()[0]) * 1000.0

for m in json.load(sys.stdin).get("all_models_loaded", []):
    if m.get("pinned") or m.get("is_busy") or m.get("is_streaming"):
        continue
    last = m.get("last_use")
    if not isinstance(last, (int, float)):
        continue
    if uptime_ms - last > idle_limit:
        print(m["model_name"])
'
)

if [ "${#victims[@]}" -eq 0 ]; then
  exit 0
fi

for model in "${victims[@]}"; do
  echo "lemonade-idle-reaper: unloading '$model' (idle > ${IDLE_SECONDS}s)"
  curl -sf --max-time 60 -X POST \
    -H "Authorization: Bearer $key" \
    -H "Content-Type: application/json" \
    -d "{\"model_name\":\"$model\"}" "$URL/api/v1/unload" >/dev/null \
    || echo "lemonade-idle-reaper: unload of '$model' failed" >&2
done
