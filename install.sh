#!/usr/bin/env bash
# Install the Teams plugin from this repo into the live Omarchy shell.
#
# The repo is the canonical copy: Omarchy rejects symlinks inside a plugin
# folder, so the files have to be copied rather than linked.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.config/omarchy/plugins/io.github.haripako.teams"
BINDIR="$HOME/.local/bin"

echo "==> Copying plugin to $DEST"
mkdir -p "$DEST"
cp "$REPO/manifest.json" "$REPO/BarWidget.qml" "$DEST/"

echo "==> Installing helper scripts to $BINDIR"
mkdir -p "$BINDIR"
install -m 0755 "$REPO/bin/omarchy-teams-close" "$BINDIR/omarchy-teams-close"

echo "==> Validating"
omarchy plugin validate "$DEST"

if command -v /usr/lib/qt6/bin/qmllint >/dev/null; then
  SHIM="$(mktemp -d)"
  ln -sfn /usr/share/omarchy/shell "$SHIM/qs"
  echo "==> qmllint (warnings about 'bar' and 'Style.font' are expected; stock widgets have them too)"
  /usr/lib/qt6/bin/qmllint -I "$SHIM" -I /usr/lib/qt6/qml "$DEST/BarWidget.qml" \
    2>&1 | grep -oE "\[[a-z-]+\]$" | sort | uniq -c || true
  rm -rf "$SHIM"
fi

# rescanPlugins discovers a plugin but keeps the old QML instance alive, so a
# full shell restart is the only way to pick up code changes.
echo "==> Restarting the Omarchy shell"
omarchy restart shell
sleep 5

echo "==> Bar placement + settings"
omarchy bar put io.github.haripako.teams --section right --index 0 || true
omarchy bar set io.github.haripako.teams homeWorkspace 1 || true

echo "==> IPC check"
# `quit` is deliberately absent: it closes the real window.
for m in toggle show hide refresh; do
  printf '    %-8s ' "$m"
  out="$(omarchy-shell teams "$m" 2>&1)" || true
  [ -z "$out" ] && echo "OK" || echo "$out"
  sleep 1
done
# The loop ends on `hide`, which would leave Teams parked on the special
# workspace after every install. Put it back where the user left it.
omarchy-shell -q teams show || true

cat <<'EOF'

Done. Two things this script deliberately does NOT do, because they append to
files you also edit by hand:

  - hypr/bindings.snippet.lua   -> append to ~/.config/hypr/bindings.lua
    (this one now matters: it is what makes SUPER+W hide Teams instead of
     closing it, via the omarchy-teams-close installed above)
  - hypr/hyprland.snippet.lua   -> append to the END of ~/.config/hypr/hyprland.lua

After appending either one: hyprctl reload && hyprctl configerrors
EOF
