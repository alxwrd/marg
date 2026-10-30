#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

# Variables
GAMEDIR="/$directory/ports/Chase_the_Pizza-arm64"

# CD and set permissions
cd $GAMEDIR
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1
$ESUDO chmod +x "$GAMEDIR/Game" "$GAMEDIR/libs/ld-linux-aarch64.so.1"

# The binary needs glibc 2.38 or newer, so it runs on the copy in libs/
echo "system glibc: $(getconf GNU_LIBC_VERSION)"
sync

# Keep the logs on the card even if the device has to be forced off
( while sleep 1; do sync; done ) &
SYNCPID=$!

LOADER="ld-linux-aarch64.so.1"
# The system's graphics libraries are in /usr/local, which the bundled loader
# wouldn't search by itself. They must come before the ones in /usr/lib
LIBPATH="$GAMEDIR/libs:$GAMEDIR:/usr/local/lib/aarch64-linux-gnu:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:/usr/lib:/lib"

# Exports
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Load the game. The process is named after the loader, not Game
$GPTOKEYB "$LOADER" &
command -v pm_platform_helper > /dev/null && pm_platform_helper "$GAMEDIR/Game"
echo "starting game"
# Through the loader, Game can't find the image embedded in its own binary.
# libpalette_fix.so replaces the bad palette from the compiler
LD_PRELOAD="$GAMEDIR/libs/libpalette_fix.so" "./libs/$LOADER" --library-path "$LIBPATH" ./Game "$GAMEDIR/game.pxt64" > "$GAMEDIR/game.log" 2>&1
echo "game exit code: $?"
kill $SYNCPID
sync

# Cleanup
if command -v pm_finish > /dev/null; then
  pm_finish
else
  $ESUDO kill -9 $(pidof gptokeyb)
  printf "\033c" > /dev/tty0
fi
