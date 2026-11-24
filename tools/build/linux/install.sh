#!/bin/sh
# Adds Retro Chess, with its icon, to the applications menu of the current user. Nothing is copied but the icons and the
# menu entry: the game stays in this folder (run this again if you move it).
#   ./install.sh            add or refresh
#   ./install.sh --remove   take the entry and the icons away
set -e
here=$(cd "$(dirname "$0")" && pwd)
data=${XDG_DATA_HOME:-$HOME/.local/share}
entry="$data/applications/retro-chess.desktop"
icons="$data/icons/hicolor"

refresh() {
	# the desktop keeps caches of the icons and of the menu: an older icon would stay without this
	touch "$icons" 2>/dev/null || true
	if command -v gtk-update-icon-cache >/dev/null 2>&1; then gtk-update-icon-cache -q -f -t "$icons" 2>/dev/null || true; fi
	if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database -q "$data/applications" 2>/dev/null || true; fi
	if command -v kbuildsycoca6 >/dev/null 2>&1; then kbuildsycoca6 >/dev/null 2>&1 || true
	elif command -v kbuildsycoca5 >/dev/null 2>&1; then kbuildsycoca5 >/dev/null 2>&1 || true; fi
}

if [ "$1" = "--remove" ]; then
	rm -f "$entry" "$icons"/*/apps/retro-chess.png
	refresh
	echo "Retro Chess is no longer in the applications menu."
	exit 0
fi

mkdir -p "$data/applications"
for png in "$here"/icons/*.png; do
	size=$(basename "$png" .png)
	mkdir -p "$icons/${size}x${size}/apps"
	cp "$png" "$icons/${size}x${size}/apps/retro-chess.png"
done
chmod +x "$here/RetroChess.x86_64"
# Exec: quoted, with the characters the desktop entry format reserves escaped
quoted=$(printf '%s' "$here/RetroChess.x86_64" | sed -e 's/[\\"`$]/\\\\&/g' -e 's/%/%%/g')
cat > "$entry" <<EOF
[Desktop Entry]
Type=Application
Name=Retro Chess
Comment=Chess, with living pieces
Exec="$quoted"
Icon=retro-chess
Terminal=false
Categories=Game;BoardGame;
StartupWMClass=Retro Chess
EOF
refresh
echo "Retro Chess is in the applications menu."
