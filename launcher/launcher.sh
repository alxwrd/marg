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
GAMEDIR="/$directory/ports/@FOLDER@"
GAMELIST="/$directory/ports/gamelist.xml"

# CD and set permissions
cd "$GAMEDIR"
exec > "$GAMEDIR/log.txt" 2>&1
$ESUDO chmod +x "$GAMEDIR/Game"
echo "system glibc: $(getconf GNU_LIBC_VERSION)"

# Show the game's image in the menu. EmulationStation reads this when it next starts
if [ ! -f "$GAMELIST" ]; then
  printf '<?xml version="1.0"?>\n<gameList>\n</gameList>\n' > "$GAMELIST"
fi
if ! grep -qF '<path>./@SCRIPT@</path>' "$GAMELIST"; then
  sed -i 's#</gameList>#\t<game>\n\t\t<path>./@SCRIPT@</path>\n\t\t<name>@TITLE@</name>\n\t\t<image>./@FOLDER@/cover.png</image>\n\t</game>\n</gameList>#' "$GAMELIST"
fi
sync

# Keep the logs on the card even if the device has to be forced off
( while sleep 1; do sync; done ) &
SYNCPID=$!

# The system's graphics libraries are in /usr/local. They must be found before the ones in /usr/lib
export LD_LIBRARY_PATH="/usr/local/lib/aarch64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Exports
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Load the game
$GPTOKEYB "Game" &
command -v pm_platform_helper > /dev/null && pm_platform_helper "$GAMEDIR/Game"
echo "starting game"
./Game > "$GAMEDIR/game.log" 2>&1
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
