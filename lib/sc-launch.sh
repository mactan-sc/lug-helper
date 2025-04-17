#!/usr/bin/env bash

################################################################################
# This script configures and launches Star Citizen.
# It is installed by the LUG Helper for a non-Lutris installation.
#
# The following .desktop files are added by wine during installation and then
# modified by the LUG Helper to call this script.
# They are automatically detected by most desktop environments for easy game
# launching.
#
################################################################################
# $HOME/Desktop/RSI Launcher.desktop
# $HOME/.local/share/applications/wine/Programs/Roberts Space Industries/RSI Launcher.desktop
################################################################################
#
# If you do not wish to use the above .desktop files, simply run this script
# from your terminal.
#
# version: 1.4
################################################################################

################################################################
# Configure the environment
# Add additional environment variables here as needed
################################################################
export WINEPREFIX="$HOME/Games/star-citizen"
launch_log="$WINEPREFIX/sc-launch.log"

export WINEDLLOVERRIDES=winemenubuilder.exe=d # Prevent updates from overwriting our .desktop entries
export WINEDEBUG=-all # Cut down on console debug messages
export EOS_USE_ANTICHEATCLIENTNULL=1
# Nvidia cache options
export __GL_SHADER_DISK_CACHE=1
export __GL_SHADER_DISK_CACHE_SIZE=10737418240
export __GL_SHADER_DISK_CACHE_PATH="$WINEPREFIX"
export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
# Mesa (AMD/Intel) shader cache options
export MESA_SHADER_CACHE_DIR="$WINEPREFIX"
export MESA_SHADER_CACHE_MAX_SIZE="10G"
# Optional HUDs
#export DXVK_HUD=fps,compiler
#export MANGOHUD=1

################################################################
# Configure the wine binaries to be used
#
# To use a custom wine runner, set the path to its bin directory
# export wine_path="/path/to/custom/runner/bin"
################################################################
export wine_path="$(command -v wine | xargs dirname)"

#############################################
# Get a shell
#############################################
# Drop us into a shell that contains the current environment
# This is useful for getting a wine control panel, debugging, etc.
# Usage: ./sc-launch.sh shell
if [ "$1" = "shell" ]; then
    echo "Entering Wine prefix maintenance shell"
    echo "Useful commands: winecfg, wine control joy.cpl, wineserver -k"
    echo "Type 'exit' when done."
    export PATH="$wine_path:$PATH"; export PS1="Wine: "

    if ! [[ -n "$2" ]]; then
        cd "$WINEPREFIX"; /usr/bin/env bash --norc; exit 0
    else
        cd "$WINEPREFIX"; /usr/bin/env bash --norc -c "$2"; exit 0
    fi
fi

#############################################
# Run optional prelaunch and postexit scripts
#############################################
# To use, update the game install paths here, create the scripts with your
# desired actions in them, then place them in your prefix directory:
# sc-prelaunch.sh and sc-postexit.sh
# Replace the trap line in the section below with the example provided here
#
# "$WINEPREFIX/sc-prelaunch.sh"
# trap "update_check; \"$wine_path\"/wineserver -k; \"$WINEPREFIX\"/sc-postexit.sh" EXIT

#############################################
# It's a trap!
#############################################
# Kill the wine prefix when this script exits
# This makes sure there will be no lingering background wine processes
update_check() {
    while "$wine_path"/winedbg --command "info proc" | grep -qi "rsi.*setup"; do
        sleep 2
    done
}
trap "update_check; \"$wine_path\"/wineserver -k" EXIT

#############################################
# Launch the game
#############################################
# To enable feral gamemode, replace the launch line below with:
# gamemoderun "$wine_path"/wine "C:\Program Files\Roberts Space Industries\RSI Launcher\RSI Launcher.exe" > "$launch_log" 2>&1
#
# To enable gamescope and feral gamemode, replace the launch line below with the
# desired gamescope arguments. For example:
# gamescope --hdr-enabled -W 2560 -H 1440 --force-grab-cursor gamemoderun "$wine_path"/wine "C:\Program Files\Roberts Space Industries\RSI Launcher\RSI Launcher.exe" > "$launch_log" 2>&1

"$wine_path"/wine "C:\Program Files\Roberts Space Industries\RSI Launcher\RSI Launcher.exe" > "$launch_log" 2>&1
