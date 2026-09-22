#!/bin/zsh
set -e

PROJECT_DIR=${0:A:h}
GODOT_BIN="/Users/minjae/Downloads/Godot.app/Contents/MacOS/Godot"

if [[ ! -x "$GODOT_BIN" ]]; then
	GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
fi

if [[ ! -x "$GODOT_BIN" ]]; then
	echo "Godot.app을 Downloads 또는 Applications 폴더에서 찾지 못했습니다."
	read "REPLY?Enter를 누르면 닫힙니다."
	exit 1
fi

exec "$GODOT_BIN" --path "$PROJECT_DIR" --scene res://test_scale_180.tscn
