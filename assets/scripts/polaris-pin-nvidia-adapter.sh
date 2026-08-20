
# Point polaris' NVENC adapter at whichever render node the nvidia driver got
# this boot, before polaris.service reads its config.
#
# /dev/dri/renderD* numbering is assigned in driver probe order, so on a machine
# with both an AMD iGPU and an NVIDIA card the two can swap across reboots and
# kernel updates. When NVENC ends up aimed at the iGPU the encoder dies at
# session time with "Configured render node [...] does not map to a CUDA device"
# and the client just sees a timeout - streaming silently breaks with no obvious
# link to the update that caused it.
#
# cuda.cpp gates its device lookup on adapter_name.starts_with("/dev/dri/renderD"),
# so a stable /dev/dri/by-path symlink cannot be used here: it would skip device
# selection entirely and fall back to CUDA device 0. The node path has to be
# literal, which is why it needs recomputing each boot.

conf="${XDG_CONFIG_HOME:-$HOME/.config}/polaris/polaris.conf"

log() { echo "polaris-pin-nvidia-adapter: $*" >&2; }

# Match on the bound driver rather than a fixed PCI address so this survives the
# card being moved to another slot.
node=''
for candidate in /dev/dri/renderD*; do
  [ -e "$candidate" ] || continue
  name="${candidate##*/}"
  driver="$(readlink -f "/sys/class/drm/$name/device/driver" 2>/dev/null)" || continue
  case "${driver##*/}" in
    nvidia) node="$candidate" ;;
    *) continue ;;
  esac
  break
done

if [ -z "$node" ]; then
  log "no render node bound to the nvidia driver; leaving adapter_name alone"
  exit 0
fi

# polaris-start seeds this file, so on a first boot it legitimately does not
# exist yet. Do nothing rather than racing it.
if [ ! -f "$conf" ]; then
  log "$conf does not exist yet; nothing to pin"
  exit 0
fi

current="$(sed -n 's/^adapter_name = //p' "$conf" | head -1)"
if [ "$current" = "$node" ]; then
  log "adapter_name already $node"
  exit 0
fi

# Preserve the existing mode (polaris writes this 0600) and never leave a
# half-written config behind if we are interrupted mid-rewrite.
tmp="$conf.pin-nvidia.$$"
trap 'rm -f "$tmp"' EXIT
if [ -n "$current" ]; then
  sed "s|^adapter_name = .*|adapter_name = $node|" "$conf" >"$tmp" || { log "rewrite failed"; exit 0; }
else
  { cat "$conf" && printf 'adapter_name = %s\n' "$node"; } >"$tmp" || { log "append failed"; exit 0; }
fi
chmod --reference="$conf" "$tmp" 2>/dev/null || chmod 600 "$tmp"
mv -f "$tmp" "$conf" || { log "could not replace $conf"; exit 0; }
trap - EXIT
log "adapter_name ${current:-<unset>} -> $node"
