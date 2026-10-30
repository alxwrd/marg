#!/bin/bash
# Turns a MakeCode Arcade .png export into a game for ports/ on the SD card.
# Usage: ./build.sh <game.png>
# Writes out/ports/<Name>/ and out/ports/<Name>.sh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
[ -f "$1" ] || { echo "usage: $0 <game.png>"; exit 1; }
PNG="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

docker build -q --platform linux/arm64 -t makecode-build "$ROOT/builder" > /dev/null

WORK="$ROOT/out/.build/$(basename "$PNG" .png)"
rm -rf "$WORK"
mkdir -p "$WORK/game"

echo "compiling the game image"
docker run --rm --platform linux/arm64 -v "$PNG":/in/game.png:ro -v "$WORK":/work \
  makecode-build /builder/build-image.sh /in/game.png /work

echo "compiling the runtime and the runner"
docker run --rm --platform linux/arm64 -v "$WORK":/work \
  makecode-build /builder/build-runtime.sh /work/tree /work/game

# The project's name can have any characters in it, but these go in paths and in sed
TITLE="$(LC_ALL=C tr -cd 'A-Za-z0-9 _-' < "$WORK/name" | sed 's/^ *//; s/ *$//')"
[ -n "$TITLE" ] || TITLE=Game
FOLDER="$(echo "$TITLE" | tr ' ' '_')"
SCRIPT="$TITLE.sh"

PORTS="$ROOT/out/ports"
GAMEDIR="$PORTS/$FOLDER"
rm -rf "$GAMEDIR"
mkdir -p "$GAMEDIR"
cp "$WORK/game/Game" "$WORK/game/libpxt.so" "$WORK/game.pxt64" "$GAMEDIR/"
cp "$PNG" "$GAMEDIR/cover.png"
sed -e "s/@FOLDER@/$FOLDER/g" -e "s/@SCRIPT@/$SCRIPT/g" -e "s/@TITLE@/$TITLE/g" \
  "$ROOT/launcher/launcher.sh" > "$PORTS/$SCRIPT"
chmod +x "$PORTS/$SCRIPT" "$GAMEDIR/Game"

# The device has glibc 2.30. Stop here if the build picked up anything newer
NEWEST="$(docker run --rm --platform linux/arm64 -v "$GAMEDIR":/game:ro makecode-build \
  sh -c 'objdump -T /game/Game /game/libpxt.so | grep -o "GLIBC_[0-9.]*" | sort -uV | tail -1')"
echo "newest glibc needed: $NEWEST"
if [ "$(printf '%s\nGLIBC_2.30\n' "$NEWEST" | sort -V | tail -1)" != GLIBC_2.30 ]; then
  echo "error: the device has only GLIBC_2.30"
  exit 1
fi
echo "done: copy these to ports/ on the SD card:"
echo "  $GAMEDIR"
echo "  $PORTS/$SCRIPT"
