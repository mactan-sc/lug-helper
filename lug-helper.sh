#!/usr/bin/env bash

############################################################################
# Star Citizen Linux Users Group Helper Script
############################################################################
#
# Greetings, Space Penguin!
#
# This script is designed to help you run Star Citizen on Linux.
#
# Please see the project's github repo for more information:
# https://github.com/starcitizen-lug/lug-helper
#
# made with <3
# Author: https://github.com/the-sane
# Contributor: https://github.com/Termuellinator
# Contributor: https://github.com/pstn
# Contributor: https://github.com/gort818
# Contributor: https://github.com/victort
# Contributor: https://github.com/Wrzlprnft
# Contributor: https://github.com/LovingMelody
# Contributor: https://github.com/mactan-sc
# Contributor: https://github.com/ProjectSynchro
# Runner Downloader inspired by:
# https://github.com/richardtatum/sc-runner-updater
#
# License: GPLv3.0
############################################################################

# Check if script is run as root
if [ "$(id -u)" -eq 0 ]; then
    echo "This script is not supposed to be run as root!"
    exit 1
fi

# Check for dependencies
if [ ! -x "$(command -v curl)" ]; then
# Print to stderr and also try warning the user through notify-send
    printf "lug-helper.sh: The required package 'curl' was not found on this system.\n" 1>&2
    notify-send "lug-helper" "The required package 'curl' was not found on this system.\n" --icon=dialog-warning
    exit 1
fi
if [ ! -x "$(command -v mktemp)" ] || [ ! -x "$(command -v chmod)" ] || [ ! -x "$(command -v sort)" ] || [ ! -x "$(command -v basename)" ] || [ ! -x "$(command -v realpath)" ] || [ ! -x "$(command -v dirname)" ] || [ ! -x "$(command -v cut)" ] || [ ! -x "$(command -v numfmt)" ] || [ ! -x "$(command -v tr)" ] || [ ! -x "$(command -v od)" ] || [ ! -x "$(command -v readlink)" ]; then
    # coreutils
    # Print to stderr and also try warning the user through notify-send
    printf "lug-helper.sh: One or more required packages were not found on this system.\nPlease check that coreutils is installed!\n" 1>&2
    notify-send "lug-helper" "One or more required packages were not found on this system.\nPlease check that coreutils is installed!\n" --icon=dialog-warning
    exit 1
fi
if [ ! -x "$(command -v xargs)" ]; then
    # findutils
    # Print to stderr and also try warning the user through notify-send
    printf "lug-helper.sh: One or more required packages were not found on this system.\nPlease check that the following findutils packages are installed:\n- xargs\n" 1>&2
    notify-send "lug-helper" "One or more required packages were not found on this system.\nPlease check that the following findutils packages are installed:\n- xargs\n" --icon=dialog-warning
    exit 1
fi
if [ ! -x "$(command -v cabextract)" ] || [ ! -x "$(command -v unzip)" ]; then
    # winetricks dependencies
    # Print to stderr and also try warning the user through notify-send
    printf "lug-helper.sh: One or more required packages were not found on this system.\nPlease check that the following winetricks dependencies (or winetricks itself) are installed:\n- cabextract\n- unzip\n" 1>&2
    notify-send "lug-helper" "One or more required packages were not found on this system.\nPlease check that the following winetricks dependencies (or winetricks itself) are installed:\n- cabextract\n- unzip\n" --icon=dialog-warning
    exit 1
fi

# Checks for NixOS for NixOS specific options
if (grep '^NAME=NixOS' /etc/os-release -q 2> /dev/null ); then
    is_nixos=1
else
    is_nixos=0
fi

######## Config ############################################################

wine_conf="winedir.conf"
game_conf="gamedir.conf"
firstrun_conf="firstrun.conf"

# Use XDG base directories if defined
if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" ]; then
    # Source the user's xdg directories
    source "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
fi
conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"

# .config subdirectory
conf_subdir="starcitizen-lug"

# Flatpak lutris directory
lutris_flatpak_dir="$HOME/.var/app/net.lutris.Lutris"

# Lutris native game configs directory
lutris_native_conf_dir="$conf_dir/lutris/games"

# Lutris flatpak game configs directory
lutris_flatpak_conf_dir="$lutris_flatpak_dir/config/lutris/games"

# Helper directory
helper_dir="$(realpath "$0" | xargs -0 dirname)"

# Temporary directory
tmp_dir="$(mktemp -d -t "lughelper.XXXXXXXXXX")"
trap 'rm -r --interactive=never "$tmp_dir"' EXIT

# Set a maximum number of versions to display from each download url
max_download_items=25

######## Game Directories ##################################################

# The game's base directory name
sc_base_dir="StarCitizen"
# The default install location within a WINE prefix:
default_install_path="drive_c/Program Files/Roberts Space Industries"

# The names of the live/ptu/eptu directories
live_dir="LIVE"
ptu_dir="PTU"
eptu_dir="EPTU"

# Location in the WINE prefix where shaders are stored
appdata_path="drive_c/users/$USER/AppData/Local/Star Citizen"

# The shaders subdirectory name
shaders_subdirs=(
    "shaders"
    "Shaders"
    "VulkanShaderCache"
)

# Remaining directory paths are set at the end of the getdirs() function

######## Bundled Files #####################################################

rsi_icon_name="rsi-launcher.png"
wine_launch_script_name="sc-launch.sh"

# Default to files in the Helper directory for a git download
rsi_icon="$helper_dir/$rsi_icon_name"
lutris_install_script="$helper_dir/lib/lutris-starcitizen.json"
wine_launch_script="$helper_dir/lib/$wine_launch_script_name"

# Build our array of search paths, supporting packaged versions of this script
# Search XDG_DATA_DIRS and fall back to /usr/share/
IFS=':' read -r -a data_dirs_array <<< "$XDG_DATA_DIRS:/usr/share/"

# Locate our files in the search array
for searchdir in "${data_dirs_array[@]}"; do
    # Check if we've found all our files and break the loop
    if [ -f "$rsi_icon" ] && [ -f "$lutris_install_script" ] && [ -f "$wine_launch_script" ]; then
        break
    fi

    # rsi-launcher.png
    if [ ! -f "$rsi_icon" ] && [ -f "$searchdir/icons/hicolor/256x256/apps/$rsi_icon_name" ]; then
        rsi_icon="$searchdir/icons/hicolor/256x256/apps/$rsi_icon_name"
    fi

    # lutris-starcitizen.json
    if [ ! -f "$lutris_install_script" ] && [ -f "$searchdir/lug-helper/lutris-starcitizen.json" ]; then
        lutris_install_script="$searchdir/lug-helper/lutris-starcitizen.json"
    fi

    # sc-launch.sh
    if [ ! -f "$wine_launch_script" ] && [ -f "$searchdir/lug-helper/$wine_launch_script_name" ]; then
        wine_launch_script="$searchdir/lug-helper/$wine_launch_script_name"
    fi
done

######## Runners ###########################################################

# Lutris native wine runners directory
runners_dir_native="$data_dir/lutris/runners/wine"
# Lutris flatpak wine runners directory
runners_dir_flatpak="$lutris_flatpak_dir/data/lutris/runners/wine"

# URLs for downloading Lutris runners
# Elements in this array must be added in quoted pairs of: "description" "url"
# The first string in the pair is expected to contain the runner description
# The second is expected to contain the api releases url
# ie. "RawFox" "https://api.github.com/repos/rawfoxDE/raw-wine/releases"
runner_sources=(
    "Kron4ek" "https://api.github.com/repos/Kron4ek/Wine-Builds/releases"
    "RawFox" "https://api.github.com/repos/starcitizen-lug/raw-wine/releases"
)

# Set the default runner to install when the system wine doesn't meet requirements
# default_runner_source corresponds to an even number index in runner_sources above
default_runner="wine-9.21-amd64.tar.xz"
default_runner_source=0

######## DXVK ##############################################################

# Lutris native dxvk directory
dxvk_dir_native="$data_dir/lutris/runtime/dxvk"
# Lutris flatpak dxvk directory
dxvk_dir_flatpak="$lutris_flatpak_dir/data/lutris/runtime/dxvk"

# URLs for downloading dxvk versions
# Elements in this array must be added in quoted pairs of: "description" "url"
# The first string in the pair is expected to contain the runner description
# The second is expected to contain the api releases url
# ie. "Sporif Async" "https://api.github.com/repos/Sporif/dxvk-async/releases"
# ie. "Ph42oN GPL+Async" "https://gitlab.com/api/v4/projects/Ph42oN%2Fdxvk-gplasync/releases"
dxvk_sources=(
    "doitsujin (standard dxvk)" "https://api.github.com/repos/doitsujin/dxvk/releases"
    "Ph42oN GPL+Async" "https://gitlab.com/api/v4/projects/Ph42oN%2Fdxvk-gplasync/releases"
)

######## Requirements ######################################################

# Wine minimum version
wine_required="9.4"

# Lutris minimum version
lutris_required="0.5.18"

# Minimum amount of RAM in GiB
memory_required="16"
# Minimum amount of combined RAM + swap in GiB
memory_combined_required="40"

######## Links / Versions ##################################################

# LUG Wiki
lug_wiki="https://starcitizen-lug.github.io"

# NixOS section in Wiki
lug_wiki_nixos="https://github.com/starcitizen-lug/knowledge-base/wiki/Tips-and-Tricks#nixos"

# RSI Installer version and url
rsi_installer="RSI Launcher-Setup-2.1.1.exe"
rsi_installer_url="https://install.robertsspaceindustries.com/rel/2/$rsi_installer"

# Winetricks download url
winetricks_version="20250102"
winetricks_url="https://raw.githubusercontent.com/Winetricks/winetricks/refs/tags/$winetricks_version/src/winetricks"

# Github repo and script version info
repo="starcitizen-lug/lug-helper"
releases_url="https://github.com/$repo/releases"
current_version="v3.7"

############################################################################
############################################################################
############################################################################


# Try to execute a supplied command as root
# Expects one string argument
try_exec() {
    # This function expects one string argument
    if [ "$#" -lt 1 ]; then
        printf "\nScript error:  The try_exec() function expects an argument. Aborting.\n"
        read -n 1 -s -p "Press any key..."
        exit 0
    fi

    # Use pollkit's pkexec for gui authentication with a fallback to sudo
    if [ -x "$(command -v pkexec)" ]; then
        pkexec sh -c "$1"

        # Check the exit status
        if [ "$?" -eq 126 ] || [ "$?" -eq 127 ]; then
            # User cancel or error
            debug_print continue "pkexec returned an error. Falling back to sudo..."
        else
            # Successful execution, return here
            return 0
        fi
    fi
    # Fall back to sudo if pkexec is unavailable or returned an error
    if [ -x "$(command -v sudo)" ]; then
        sudo sh -c "$1"

        # Check the exit status
        if [ "$?" -eq 1 ]; then
            # Error
            return 1
        fi
    else
        # We don't know how to perform this operation with elevated privileges
        printf "\nNeither Polkit nor sudo appear to be installed. Unable to execute the command with the required privileges.\n"
        return 1
    fi

    return 0
}

# Echo a formatted debug message to the terminal and optionally exit
# Accepts either "continue" or "exit" as the first argument
# followed by the string to be echoed
debug_print() {
    # This function expects two string arguments
    if [ "$#" -lt 2 ]; then
        printf "\nScript error:  The debug_print function expects two arguments. Aborting.\n"
        read -n 1 -s -p "Press any key..."
        exit 0
    fi

    # Echo the provided string and, optionally, exit the script
    case "$1" in
        "continue")
            printf "\n%s\n" "$2"
            ;;
        "exit")
            # Write an error to stderr and exit
            printf "%s\n" "lug-helper.sh: $2" 1>&2
            read -n 1 -s -p "Press any key..."
            exit 1
            ;;
        *)
            printf "%s\n" "lug-helper.sh: Unknown argument provided to debug_print function. Aborting." 1>&2
            read -n 1 -s -p "Press any key..."
            exit 0
            ;;
    esac
}

# Display a message to the user.
# Expects the first argument to indicate the message type, followed by
# a string of arguments that will be passed to zenity or echoed to the user.
#
# To call this function, use the following format: message [type] "[string]"
# See the message types below for instructions on formatting the string.
message() {
    # Sanity check
    if [ "$#" -lt 2 ]; then
        debug_print exit "Script error: The message function expects at least two arguments. Aborting."
    fi

    # Use zenity messages if available
    if [ "$use_zenity" -eq 1 ]; then
        case "$1" in
            "info")
                # info message
                # call format: message info "text to display"
                margs=("--info" "--no-wrap" "--text=")
                shift 1   # drop the message type argument and shift up to the text
                ;;
            "warning")
                # warning message
                # call format: message warning "text to display"
                margs=("--warning" "--text=")
                shift 1   # drop the message type argument and shift up to the text
                ;;
            "error")
                # error message
                # call format: message error "text to display"
                margs=("--error" "--text=")
                shift 1   # drop the message type argument and shift up to the text
                ;;
            "question")
                # question
                # call format: if message question "question to ask?"; then...
                margs=("--question" "--text=")
                shift 1   # drop the message type argument and shift up to the text
                ;;
            "options")
                # formats the buttons with two custom options
                # call format: if message options left_button_name right_button_name "which one do you want?"; then...
                # The right button returns 0 (ok), the left button returns 1 (cancel)
                if [ "$#" -lt 4 ]; then
                    debug_print exit "Script error: The options type in the message function expects four arguments. Aborting."
                fi
                margs=("--question" "--cancel-label=$2" "--ok-label=$3" "--text=")
                shift 3   # drop the type and button label arguments and shift up to the text
                ;;
            *)
                debug_print exit "Script Error: Invalid message type passed to the message function. Aborting."
                ;;
        esac

        # Display the message
        zenity "${margs[@]}""$@" --width="420" --title="Star Citizen LUG Helper"
    else
        # Fall back to text-based messages when zenity is not available
        case "$1" in
            "info")
                # info message
                # call format: message info "text to display"
                printf "\n$2\n\n"
                if [ "$cmd_line" != "true" ]; then
                    # Don't pause if we've been invoked via command line arguments
                    read -n 1 -s -p "Press any key..."
                fi
                ;;
            "warning")
                # warning message
                # call format: message warning "text to display"
                printf "\n$2\n\n"
                read -n 1 -s -p "Press any key..."
                ;;
            "error")
                # error message. Does not clear the screen
                # call format: message error "text to display"
                printf "\n$2\n\n"
                read -n 1 -s -p "Press any key..."
                ;;
            "question")
                # question
                # call format: if message question "question to ask?"; then...
                printf "\n$2\n"
                while read -p "[y/n]: " yn; do
                    case "$yn" in
                        [Yy]*)
                            return 0
                            ;;
                        [Nn]*)
                            return 1
                            ;;
                        *)
                            printf "Please type 'y' or 'n'\n"
                            ;;
                    esac
                done
                ;;
            "options")
                # Choose from two options
                # call format: if message options left_button_name right_button_name "which one do you want?"; then...
                printf "\n$4\n1: $3\n2: $2\n"
                while read -p "[1/2]: " option; do
                    case "$option" in
                        1*)
                            return 0
                            ;;
                        2*)
                            return 1
                            ;;
                        *)
                            printf "Please type '1' or '2'\n"
                            ;;
                    esac
                done
                ;;
            *)
                debug_print exit "Script Error: Invalid message type passed to the message function. Aborting."
                ;;
        esac
    fi
}

# Display a menu to the user.
# Uses Zenity for a gui menu with a fallback to plain old text.
#
# How to call this function:
#
# Requires the following variables:
# - The array "menu_options" should contain the strings of each option.
# - The array "menu_actions" should contain function names to be called.
# - The strings "menu_text_zenity" and "menu_text_terminal" should contain
#   the menu description formatted for zenity and the terminal, respectively.
#   This text will be displayed above the menu options.
#   Zenity supports Pango Markup for text formatting.
# - The integer "menu_height" specifies the height of the zenity menu.
# - The string "menu_type" should contain either "radiolist" or "checklist".
# - The string "cancel_label" should contain the text of the cancel button.
#
# The final element in each array is expected to be a quit option.
#
# IMPORTANT: The indices of the elements in "menu_actions"
# *MUST* correspond to the indeces in "menu_options".
# In other words, it is expected that menu_actions[1] is the correct action
# to be executed when menu_options[1] is selected, and so on for each element.
#
# See MAIN at the bottom of this script for an example of generating a menu.
menu() {
    # Sanity checks
    if [ "${#menu_options[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'menu_options' was not set before calling the menu function. Aborting."
    elif [ "${#menu_actions[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'menu_actions' was not set before calling the menu function. Aborting."
    elif [ -z "$menu_text_zenity" ]; then
        debug_print exit "Script error: The string 'menu_text_zenity' was not set before calling the menu function. Aborting."
    elif [ -z "$menu_text_terminal" ]; then
        debug_print exit "Script error: The string 'menu_text_terminal' was not set before calling the menu function. Aborting."
    elif [ -z "$menu_height" ]; then
        debug_print exit "Script error: The string 'menu_height' was not set before calling the menu function. Aborting."
    elif [ "$menu_type" != "radiolist" ] && [ "$menu_type" != "checklist" ]; then
        debug_print exit "Script error: Unknown menu_type in menu() function. Aborting."
    elif [ -z "$cancel_label" ]; then
        debug_print exit "Script error: The string 'cancel_label' was not set before calling the menu function. Aborting."
    fi

    # Use Zenity if it is available
    if [ "$use_zenity" -eq 1 ]; then
        # Format the options array for Zenity by adding
        # TRUE or FALSE to indicate default selections
        # ie: "TRUE" "List item 1" "FALSE" "List item 2" "FALSE" "List item 3"
        unset zen_options
        for (( i=0; i<"${#menu_options[@]}"-1; i++ )); do
            if [ "$i" -eq 0 ]; then
                # Set the first element
                if [ "$menu_type" = "radiolist" ]; then
                    # Select the first radio button by default
                    zen_options=("TRUE")
                else
                    # Don't select the first checklist item
                    zen_options=("FALSE")
                fi
            else
                # Deselect all remaining items
                zen_options+=("FALSE")
            fi
            # Add the menu list item
            zen_options+=("${menu_options[i]}")
        done

        # Display the zenity radio button menu
        choice="$(zenity --list --"$menu_type" --width="510" --height="$menu_height" --text="$menu_text_zenity" --title="Star Citizen LUG Helper" --hide-header --cancel-label "$cancel_label" --column="" --column="Option" "${zen_options[@]}")"

        # Match up choice with an element in menu_options
        matched="false"
        if [ "$menu_type" = "radiolist" ]; then
            # Loop through the options array to match the chosen option
            for (( i=0; i<"${#menu_options[@]}"; i++ )); do
                if [ "$choice" = "${menu_options[i]}" ]; then
                    # Execute the corresponding action for a radiolist menu
                    ${menu_actions[i]}
                    matched="true"
                    break
                fi
            done
        elif [ "$menu_type" = "checklist" ]; then
            # choice will be empty if no selection was made
            # Unfortunately, it's also empty when the user presses cancel
            # so we can't differentiate between those two states

            # Convert choice string to array elements for checklists
            IFS='|' read -r -a choices <<< "$choice"

            # Fetch the function to be called
            function_call="$(echo "${menu_actions[0]}" | awk '{print $1}')"

            # Loop through the options array to match the chosen option(s)
            unset arguments_array
            for (( i=0; i<"${#menu_options[@]}"; i++ )); do
                for (( j=0; j<"${#choices[@]}"; j++ )); do
                    if [ "${choices[j]}" = "${menu_options[i]}" ]; then
                        arguments_array+=("$(echo "${menu_actions[i]}" | awk '{print $2}')")
                        matched="true"
                    fi
                done
            done

            # Call the function with all matched elements as arguments
            if [ "$matched" = "true" ]; then
                $function_call "${arguments_array[@]}"
            fi
        fi

        # If no match was found, the user clicked cancel
        if [ "$matched" = "false" ]; then
            # Execute the last option in the actions array
            "${menu_actions[${#menu_actions[@]}-1]}"
        fi
    else
        # Use a text menu if Zenity is not available
        clear
        printf "\n$menu_text_terminal\n\n"

        PS3="Enter selection number: "
        select choice in "${menu_options[@]}"
        do
            # Loop through the options array to match the chosen option
            matched="false"
            for (( i=0; i<"${#menu_options[@]}"; i++ )); do
                if [ "$choice" = "${menu_options[i]}" ]; then
                    clear
                    # Execute the corresponding action
                    ${menu_actions[i]}
                    matched="true"
                    break
                fi
            done

            # Check if we're done looping the menu
            if [ "$matched" = "true" ]; then
                # Match was found and actioned, so exit the menu
                break
            else
                # If no match was found, the user entered an invalid option
                printf "\nInvalid selection.\n"
                continue
            fi
        done
    fi
}

# Called when the user clicks cancel on a looping menu
# Causes a return to the main menu
menu_loop_done() {
    looping_menu="false"
}

# Get paths to the user's wine prefix, game directory, and a backup directory
# Returns 3 if the user was asked to select new directories
getdirs() {
    # Sanity checks
    if [ ! -d "$conf_dir" ]; then
        message error "Config directory not found. The Helper is unable to proceed.\n\n$conf_dir"
        return 1
    fi
    if [ ! -d "$conf_dir/$conf_subdir" ]; then
        mkdir -p "$conf_dir/$conf_subdir"
    fi

    # Initialize a return value
    retval=0

    # Check if the config files already exist
    if [ -f "$conf_dir/$conf_subdir/$wine_conf" ]; then
        wine_prefix="$(cat "$conf_dir/$conf_subdir/$wine_conf")"
        if [ ! -d "$wine_prefix" ]; then
            debug_print continue "The saved wine prefix does not exist, ignoring."
            wine_prefix=""
            rm --interactive=never "${conf_dir:?}/$conf_subdir/$wine_conf"
        fi
    fi
    if [ -f "$conf_dir/$conf_subdir/$game_conf" ]; then
        game_path="$(cat "$conf_dir/$conf_subdir/$game_conf")"
        # Note: We check for the parent dir here because the game may not have been fully installed yet
        # which  means sc_base_dir may not yet have been created. But the parent RSI dir must exist
        if [ ! -d "$(dirname "$game_path")" ] || [ "$(basename "$game_path")" != "$sc_base_dir" ]; then
            debug_print continue "Unexpected game path found in config file, ignoring."
            game_path=""
            rm --interactive=never "${conf_dir:?}/$conf_subdir/$game_conf"
        fi
    fi

    # If we don't have the directory paths we need yet,
    # ask the user to provide them
    if [ -z "$wine_prefix" ] || [ -z "$game_path" ]; then
        message info "At the next screen, please select the directory where you installed Star Citizen (your Wine prefix)\nIt will be remembered for future use.\n\nDefault install path: ~/Games/star-citizen"
        if [ "$use_zenity" -eq 1 ]; then
            # Using Zenity file selection menus
            # Get the wine prefix directory
            while [ -z "$wine_prefix" ]; do
                wine_prefix="$(zenity --file-selection --directory --title="Select your Star Citizen Wine prefix directory" --filename="$HOME/Games/star-citizen" 2>/dev/null)"
                if [ "$?" -eq -1 ]; then
                    message error "An unexpected error has occurred. The Helper is unable to proceed."
                    return 1
                elif [ -z "$wine_prefix" ]; then
                    # User clicked cancel
                    message warning "Operation cancelled.\nNo changes have been made to your game."
                    return 1
                fi

                if ! message question "You selected:\n\n$wine_prefix\n\nIs this correct?"; then
                    wine_prefix=""
                fi
            done

            # Get the game path
            if [ -z "$game_path" ]; then
                if [ -d "$wine_prefix/$default_install_path" ]; then
                    # Default: prefix/drive_c/Program Files/Roberts Space Industries/StarCitizen
                    game_path="$wine_prefix/$default_install_path/$sc_base_dir"
                else
                    message info "Unable to detect the default game install path!\n\n$wine_prefix/$default_install_path/$sc_base_dir\n\nDid you change the install location in the RSI Setup?\nDoing that is generally a bad idea but, if you are sure you want to proceed,\nselect your '$sc_base_dir' game directory on the next screen"
                    while true; do
                        game_path="$(zenity --file-selection --directory --title="Select your Star Citizen directory" --filename="$wine_prefix/$default_install_path" 2>/dev/null)"

                        if [ "$?" -eq -1 ]; then
                            message error "An unexpected error has occurred. The Helper is unable to proceed."
                            return 1
                        elif [ -z "$game_path" ]; then
                            # User clicked cancel or something else went wrong
                            message warning "Operation cancelled.\nNo changes have been made to your game."
                            return 1
                        elif [ "$(basename "$game_path")" != "$sc_base_dir" ]; then
                            message warning "You must select the base game directory named '$sc_base_dir'\n\nie. [prefix]/drive_c/Program Files/Roberts Space Industries/StarCitizen"
                        else
                            # All good
                            break
                        fi
                    done
                fi
            fi
        else
            # No Zenity, use terminal-based menus
            clear
            # Get the wine prefix directory
            if [ -z "$wine_prefix" ]; then
                printf "Enter the full path to your Star Citizen Wine prefix directory (case sensitive)\n"
                printf "ie. /home/USER/Games/star-citizen\n"
                while read -rp ": " wine_prefix; do
                    if [ ! -d "$wine_prefix" ]; then
                        printf "That directory is invalid or does not exist. Please try again.\n\n"
                    else
                        break
                    fi
                done
            fi

            # Get the game path
            if [ -z "$game_path" ]; then
                if [ -d "$wine_prefix/$default_install_path/s" ]; then
                    # Default: prefix/drive_c/Program Files/Roberts Space Industries/StarCitizen
                    game_path="$wine_prefix/$default_install_path/$sc_base_dir"
                else
                    printf "\nUnable to detect the default game install path!\nDid you change the install location in the RSI Setup?\nDoing that is generally a bad idea but, if you are sure you want to proceed...\n\n"
                    printf "Enter the full path to your $sc_base_dir installation directory (case sensitive)\n"
                    printf "ie. /home/USER/Games/star-citizen/drive_c/Program Files/Roberts Space Industries/StarCitizen\n"
                    while read -rp ": " game_path; do
                        if [ ! -d "$game_path" ]; then
                            printf "That directory is invalid or does not exist. Please try again.\n\n"
                        elif [ "$(basename "$game_path")" != "$sc_base_dir" ]; then
                            printf "You must enter the full path to the directory named '%s'\n\n" "$sc_base_dir"
                        else
                            break
                        fi
                    done
                fi
            fi
        fi

        # Set a return code to indicate to other functions in this script that the user had to select new directories here
        retval=3
    fi

    # Save the paths to config files
    if [ ! -f "$conf_dir/$conf_subdir/$wine_conf" ]; then
        echo "$wine_prefix" > "$conf_dir/$conf_subdir/$wine_conf"
    fi
    if [ ! -f "$conf_dir/$conf_subdir/$game_conf" ]; then
        echo "$game_path" > "$conf_dir/$conf_subdir/$game_conf"
    fi

    ######## Set remaining directory paths #####################################
    # $game_version is set in the version_menu() function
    ############################################################################
    # The game's user directory
    if [ -d "$game_path/$game_version/USER/Client" ]; then
        # Backwards compatibility for older installs
        user_dir="$game_path/$game_version/USER/Client/0"
    else
        user_dir="$game_path/$game_version/user/client/0"
    fi
    # The location within the USER directory to which the game exports keybinds
    keybinds_dir="$user_dir/Controls/Mappings"
    # Shaders directory
    shaders_dir="$wine_prefix/$appdata_path"
    # Custom characters directory
    custom_characters_dir="$user_dir/CustomCharacters"
    # dxvk cache file
    dxvk_cache="$game_path/$game_version/StarCitizen.dxvk-cache"
    # Where to store backed up keybinds
    backup_path="$conf_dir/$conf_subdir"

    return "$retval"
}


############################################################################
######## begin preflight check functions ###################################
############################################################################

# Check that the system is optimized for Star Citizen
# Accepts an optional string argument, "lutris" or "wine"
# This argument is used by the install functions to indicate which
# Preflight Check functions should be called and cause the Preflight Check
# to only output problems that must be fixed
preflight_check() {
    # Initialize variables
    unset preflight_pass
    unset preflight_fail
    unset preflight_action_funcs
    unset preflight_actions
    unset preflight_fix_results
    unset preflight_manual
    unset preflight_followup
    unset preflight_fail_string
    unset preflight_pass_string
    unset preflight_fix_results_string
    unset install_mode
    retval=0

    # Capture optional argument that determines which install function called us
    install_mode="$1"

    # Check the optional argument for valid values
    if [ -n "$install_mode" ] && [ "$install_mode" != "wine" ] && [ "$install_mode" != "lutris" ]; then
        debug_print exit "Script error: Unexpected argument passed to the preflight_check function. Aborting."
    fi

    # Call the optimization functions to perform the checks
    if [ "$install_mode" != "wine" ]; then
        # Don't check for lutris if called from the wine install function
        lutris_check
    fi
    wine_check
    memory_check
    avx_check
    mapcount_check
    filelimit_check

    # Populate info strings with the results and add formatting
    if [ "${#preflight_fail[@]}" -gt 0 ]; then
        # Failed checks
        preflight_fail_string="Failed Checks:"
        for (( i=0; i<"${#preflight_fail[@]}"; i++ )); do
            if [ "$i" -eq 0 ]; then
                preflight_fail_string="$preflight_fail_string\n- ${preflight_fail[i]//\\n/\\n    }"
            else
                preflight_fail_string="$preflight_fail_string\n\n- ${preflight_fail[i]//\\n/\\n    }"
            fi
        done
        # Add extra newlines if there are also passes to report
        if [ "${#preflight_pass[@]}" -gt 0 ]; then
            preflight_fail_string="$preflight_fail_string\n\n"
        fi
    fi
    if [ "${#preflight_pass[@]}" -gt 0 ]; then
        # Passed checks
        preflight_pass_string="Passed Checks:"
        for (( i=0; i<"${#preflight_pass[@]}"; i++ )); do
            preflight_pass_string="$preflight_pass_string\n- ${preflight_pass[i]//\\n/\\n    }"
        done
    fi
    for (( i=0; i<"${#preflight_manual[@]}"; i++ )); do
        # Instructions for manually fixing problems
        if [ "$i" -eq 0 ]; then
            preflight_manual_string="${preflight_manual[i]}"
        else
            preflight_manual_string="$preflight_manual_string\n\n${preflight_manual[i]}"
        fi
    done

    # Format a message heading
    message_heading="Preflight Check Results"
    if [ "$use_zenity" -eq 1 ]; then
        message_heading="<big><b>$message_heading</b></big>"
    fi

    # Display the results of the preflight check
    if [ -z "$preflight_fail_string" ]; then
        # If install_mode was set by an install function, we won't bother the user when all checks pass
        if [ -z "$install_mode" ]; then
            # All checks pass!
            message info "$message_heading\n\nYour system is optimized for Star Citizen!\n\n$preflight_pass_string"
        fi

        return 0
    else
        if [ "${#preflight_action_funcs[@]}" -eq 0 ]; then
            # We have failed checks, but they're issues we can't automatically fix
            message warning "$message_heading\n\n$preflight_fail_string$preflight_pass_string"
        elif message question "$message_heading\n\n$preflight_fail_string$preflight_pass_string\n\nWould you like these configuration issues to be fixed for you?"; then
            # We have failed checks, but we can fix them for the user
            # Call functions to build fixes for any issues found
            for (( i=0; i<"${#preflight_action_funcs[@]}"; i++ )); do
                ${preflight_action_funcs[i]}
            done
            # Populate a string of actions to be executed
            for (( i=0; i<"${#preflight_actions[@]}"; i++ )); do
                if [ "$i" -eq 0 ]; then
                    preflight_actions_string="${preflight_actions[i]}"
                else
                    preflight_actions_string="$preflight_actions_string; ${preflight_actions[i]}"
                fi
            done

            # Execute the actions set by the functions
            if [ -n "$preflight_actions_string" ]; then
                # Try to execute the actions as root
                try_exec "$preflight_actions_string"
                if [ "$?" -eq 1 ]; then
                    message error "Authentication failed or there was an error.\nSee terminal for more information.\n\nReturning to main menu."
                    return 0
                fi
            fi

            # Call any followup functions
            for (( i=0; i<"${#preflight_followup[@]}"; i++ )); do
                ${preflight_followup[i]}
            done

            # Populate the results string
            for (( i=0; i<"${#preflight_fix_results[@]}"; i++ )); do
                if [ "$i" -eq 0 ]; then
                    preflight_fix_results_string="${preflight_fix_results[i]}"
                else
                    preflight_fix_results_string="$preflight_fix_results_string\n\n${preflight_fix_results[i]}"
                fi
            done

            # Display the results
            message info "$preflight_fix_results_string"
        else
            # User declined to automatically fix configuration issues
            # Show manual configuration options
            if [ -n "$preflight_manual_string" ]; then
                message info "$preflight_manual_string"
            fi
        fi

        return 1
    fi
}

# Check the installed lutris version
lutris_check() {
    lutris_detect

    if [ "$lutris_installed" = "false" ]; then
        preflight_fail+=("Lutris does not appear to be installed.\nFor non-Lutris installs, this may be ignored.")
        return 1
    fi

    # Check the native lutris version number
    if [ "$lutris_native" = "true" ]; then
        lutris_current="$(lutris -v 2>/dev/null | awk -F '-' '{print $2}')"
        if [ -z "$lutris_current" ]; then
            preflight_fail+=("Unable to detect Lutris version info.\nVersion $lutris_required or newer is required.")
        elif [ "$lutris_required" != "$lutris_current" ] &&
            [ "$lutris_current" = "$(printf "%s\n%s" "$lutris_current" "$lutris_required" | sort -V | head -n1)" ]; then
            preflight_fail+=("Lutris is out of date.\nVersion $lutris_required or newer is required.")
        else
            preflight_pass+=("Lutris is installed and sufficiently up to date.")
        fi
    fi

    # Check the flatpak lutris version number
    if [ "$lutris_flatpak" = "true" ]; then
        lutris_current="$(flatpak run net.lutris.Lutris -v 2>/dev/null | awk -F '-' '{print $2}')"
        if [ -z "$lutris_current" ]; then
            preflight_fail+=("Unable to detect Flatpak Lutris version info.\nVersion $lutris_required or newer is required.")
        elif [ "$lutris_required" != "$lutris_current" ] &&
            [ "$lutris_current" = "$(printf "%s\n%s" "$lutris_current" "$lutris_required" | sort -V | head -n1)" ]; then
            preflight_fail+=("Flatpak Lutris is out of date.\nVersion $lutris_required or newer is required.")
        else
            preflight_pass+=("Flatpak Lutris is installed and sufficiently up to date.")
        fi
    fi
}

# Detect if lutris is installed
lutris_detect() {
    lutris_installed="false"
    lutris_native="false"
    lutris_flatpak="false"

    # Detect native lutris
    if [ -x "$(command -v lutris)" ]; then
        lutris_installed="true"
        lutris_native="true"
    fi

    # Detect flatpak lutris
    if [ -x "$(command -v flatpak)" ] && flatpak list --app | grep -q Lutris; then
            lutris_installed="true"
            lutris_flatpak="true"
    fi
}

# Check the system Wine version
# Tells the preflight check whether or not wine is installed
# Additionally sets system_wine_ok if system wine meets the minimum version requirement
wine_check() {
    # Initialize variable
    system_wine_ok="false"

    # Is wine installed?
    if [ ! -x "$(command -v wine)" ]; then
        preflight_fail+=("Wine does not appear to be installed.\nPlease refer to our Quick Start Guide:\n$lug_wiki")
        return 1
    else
        preflight_pass+=("Wine is installed on your system.")
    fi

    # Get the current wine version
    wine_current="$(wine --version 2>/dev/null | awk '{print $1}' | awk -F '-' '{print $2}')"

    # Check it against the required version
    if [ -z "$wine_current" ]; then
        system_wine_ok="false"
    elif [ "$wine_required" != "$wine_current" ] &&
        [ "$wine_current" = "$(printf "%s\n%s" "$wine_current" "$wine_required" | sort -V | head -n1)" ]; then
        system_wine_ok="false"
    else
        system_wine_ok="true"
    fi

    # If system wine passes the above checks, also check for the new wow64 mode that currently does not work
    if [ "$system_wine_ok" = "true" ]; then
        # Get paths to wine and wineserver binaries
        wine_bin="$(command -v wine)"
        wineserver_bin="$(command -v wineserver)"
        wineboot_bin="$(command -v wineboot)"

        # Determine the architecture of wine binary
        wine_bin_arch="$(get_file_arch "${wine_bin}")"

        # If unable to determine architecture, attempt alternative methods
        if [ -z "${wine_bin_arch}" ]; then
            if [ -x "${wineboot_bin}" ]; then
                wine_bin_dir="$(dirname "$(readlink -f "${wineboot_bin}" 2>/dev/null)" 2>/dev/null)"
                if [ -x "${wine_bin_dir}/wine" ]; then
                    wine_bin_arch="$(get_file_arch "${wine_bin_dir}/wine")"
                fi
            fi
        fi

        # Determine the architecture of wineserver binary
        wineserver_bin_arch="$(get_file_arch "${wineserver_bin}")"

        # If unable to determine architecture, attempt alternative methods
        if [ -z "${wineserver_bin_arch}" ]; then
            if [ -x "${wineboot_bin}" ]; then
                wine_bin_dir="$(dirname "$(readlink -f "${wineboot_bin}" 2>/dev/null)" 2>/dev/null)"
                if [ -x "${wine_bin_dir}/wineserver64" ]; then
                    wineserver_bin_arch="$(get_file_arch "${wine_bin_dir}/wineserver64")"
                elif [ -x "${wine_bin_dir}/wineserver32" ]; then
                    wineserver_bin_arch="$(get_file_arch "${wine_bin_dir}/wineserver32")"
                elif [ -x "${wine_bin_dir}/wineserver" ]; then
                    wineserver_bin_arch="$(get_file_arch "${wine_bin_dir}/wineserver")"
                fi
            fi
        fi

        # Check for the new WOW64, 32bit, or unknown states and then fail the check
        if [ "${wineserver_bin_arch}" = "${wine_bin_arch}" ] || [ -z "${wineserver_bin_arch}" ] || [ -z "${wine_bin_arch}" ]; then
            system_wine_ok="false"
        fi
    fi
}

# Determine the architecture of a binary file
# Used for wine_check above to check the system wine
get_file_arch() {
    case "$(od -An -t x1 -j 0x12 -N 1 "$1" 2>/dev/null | tr -d '[:space:]')" in
        "3e")
            # x86_64
            echo "64bit"
            ;;
        "03"|"06")
            # i386
            echo "32bit"
            ;;
        "b7")
            # aarch64
            echo "64bit"
            ;;
        "28")
            # aarch32
            echo "32bit"
            ;;
        *)
            # Unknown
            echo ""
            ;;
    esac
}

# Check system memory and swap space
memory_check() {
    # Get totals in bytes
    memtotal="$(LC_NUMERIC=C awk '/MemTotal/ {printf $2}' /proc/meminfo)"
    swaptotal="$(LC_NUMERIC=C awk '/SwapTotal/ {printf $2}' /proc/meminfo)"
    memtotal="$(($memtotal * 1024))"
    swaptotal="$(($swaptotal * 1024))"
    combtotal="$(($memtotal + $swaptotal))"

    # Convert to whole number GiB
    memtotal="$(numfmt --to=iec-i --format="%.0f" --suffix="B" "$memtotal")"
    swaptotal="$(numfmt --to=iec-i --format="%.0f" --suffix="B" "$swaptotal")"
    combtotal="$(numfmt --to=iec-i --format="%.0f" --suffix="B" "$combtotal")"

    if [ "${memtotal: -3}" != "GiB" ] || [ "${memtotal::-3}" -lt "$(($memory_required-1))" ]; then
        # Minimum requirements are not met
        preflight_fail+=("Your system has $memtotal of memory.\n${memory_required}GiB is the minimum required to avoid crashes.")
    elif [ "${memtotal::-3}" -ge "$memory_combined_required" ]; then
        # System has sufficient RAM
        preflight_pass+=("Your system has $memtotal of memory.")
    elif [ "${combtotal::-3}" -ge "$memory_combined_required" ]; then
        # System has sufficient combined RAM + swap
        preflight_pass+=("Your system has $memtotal memory and $swaptotal swap.")
    else
        # Recommend swap
        swap_recommended="$(($memory_combined_required - ${memtotal::-3}))"
        preflight_fail+=("Your system has $memtotal memory and $swaptotal swap.\nWe recommend at least ${swap_recommended}GiB swap to avoid crashes.")
    fi
}

# Check CPU for the required AVX extension
avx_check() {
    if grep -q "avx" /proc/cpuinfo; then
        preflight_pass+=("Your CPU supports the necessary AVX instruction set.")
    else
        preflight_fail+=("Your CPU does not appear to support AVX instructions.\nThis requirement was added to Star Citizen in version 3.11")
    fi
}

############################################################################
######## begin mapcount functions ##########################################
############################################################################

# Check vm.max_map_count for the correct setting
mapcount_check() {
    mapcount="$(cat /proc/sys/vm/max_map_count)"
    # Add to the results and actions arrays
    if [ "$mapcount" -ge 16777216 ]; then
        # All good
        preflight_pass+=("vm.max_map_count is set to $mapcount.")
    elif grep -E -x -q "vm.max_map_count" /etc/sysctl.conf /etc/sysctl.d/* 2>/dev/null; then
        # Was it supposed to have been set by sysctl?
        preflight_fail+=("vm.max_map_count is configured to at least 16777216 but the setting has not been loaded by your system.")
        # Add the function that will be called to change the configuration
        preflight_action_funcs+=("mapcount_once")

        # Add info for manually changing the setting
        preflight_manual+=("To change vm.max_map_count until the next reboot, run:\nsudo sysctl -w vm.max_map_count=16777216")
    else
        # The setting should be changed
        preflight_fail+=("vm.max_map_count is $mapcount\nand should be set to at least 16777216\nto give the game access to sufficient memory.")
        # Add the function that will be called to change the configuration
        preflight_action_funcs+=("mapcount_set")

        # Add info for manually changing the setting
        if [ -d "/etc/sysctl.d" ]; then
            # Newer versions of sysctl
            preflight_manual+=("To change vm.max_map_count permanently, add the following line to\n'/etc/sysctl.d/99-starcitizen-max_map_count.conf' and reload with 'sudo sysctl --system'\n    vm.max_map_count = 16777216\n\nOr, to change vm.max_map_count temporarily until next boot, run:\n    sudo sysctl -w vm.max_map_count=16777216")
        else
            # Older versions of sysctl
            preflight_manual+=("To change vm.max_map_count permanently, add the following line to\n'/etc/sysctl.conf' and reload with 'sudo sysctl -p':\n    vm.max_map_count = 16777216\n\nOr, to change vm.max_map_count temporarily until next boot, run:\n    sudo sysctl -w vm.max_map_count=16777216")
        fi
    fi
}

# Set vm.max_map_count
mapcount_set() {
    if [ -d "/etc/sysctl.d" ]; then
        # Newer versions of sysctl
        preflight_actions+=('printf "\n# Added by LUG-Helper:\nvm.max_map_count = 16777216\n" > /etc/sysctl.d/99-starcitizen-max_map_count.conf && sysctl --quiet --system')
        preflight_fix_results+=("The vm.max_map_count configuration has been added to:\n/etc/sysctl.d/99-starcitizen-max_map_count.conf")
    else
        # Older versions of sysctl
        preflight_actions+=('printf "\n# Added by LUG-Helper:\nvm.max_map_count = 16777216" >> /etc/sysctl.conf && sysctl -p')
        preflight_fix_results+=("The vm.max_map_count configuration has been added to:\n/etc/sysctl.conf")
    fi

    # Verify that the setting took effect
    preflight_followup+=("mapcount_confirm")
}

# Sets vm.max_map_count for the current session only
mapcount_once() {
    preflight_actions+=('sysctl -w vm.max_map_count=16777216')
    preflight_fix_results+=("vm.max_map_count was changed until the next boot.")
    preflight_followup+=("mapcount_confirm")
}

# Check if setting vm.max_map_count was successful
mapcount_confirm() {
    if [ "$(cat /proc/sys/vm/max_map_count)" -lt 16777216 ]; then
        preflight_fix_results+=("WARNING: As far as this Helper can detect, vm.max_map_count\nwas not successfully configured on your system.\nYou will most likely experience crashes.")
    fi
}

############################################################################
######## end mapcount functions ############################################
############################################################################

############################################################################
######## begin filelimit functions #########################################
############################################################################

# Check the open file descriptors limit
filelimit_check() {
    filelimit="$(ulimit -Hn)"

    # Add to the results and actions arrays
    if [ "$filelimit" -ge 524288 ]; then
        # All good
        preflight_pass+=("Hard open file descriptors limit is set to $filelimit.")
    else
        # The file limit should be changed
        preflight_fail+=("Your hard open file descriptors limit is $filelimit\nand should be set to at least 524288\nto increase the maximum number of open files.")
        # Add the function that will be called to change the configuration
        preflight_action_funcs+=("filelimit_set")

        # Add info for manually changing the settings
        if [ -f "/etc/systemd/system.conf" ]; then
            # Using systemd
            preflight_manual+=("To change your open file descriptors limit, add the following to\n'/etc/systemd/system.conf.d/99-starcitizen-filelimit.conf':\n\n[Manager]\nDefaultLimitNOFILE=524288")
        elif [ -f "/etc/security/limits.conf" ]; then
            # Using limits.conf
            preflight_manual+=("To change your open file descriptors limit, add the following line to\n'/etc/security/limits.conf':\n    * hard nofile 524288")
        else
            # Don't know what method to use
            preflight_manual+=("This Helper is unable to detect the correct method of setting\nthe open file descriptors limit on your system.\n\nWe recommend manually configuring this limit to at least 524288.")
        fi
    fi
}

# Set the open file descriptors limit
filelimit_set() {
    if [ -f "/etc/systemd/system.conf" ]; then
        # Using systemd
        # Append to the file
        preflight_actions+=('mkdir -p /etc/systemd/system.conf.d && printf "[Manager]\n# Added by LUG-Helper:\nDefaultLimitNOFILE=524288\n" > /etc/systemd/system.conf.d/99-starcitizen-filelimit.conf && systemctl daemon-reexec')
        preflight_fix_results+=("The open files limit configuration has been added to:\n/etc/systemd/system.conf.d/99-starcitizen-filelimit.conf")
    elif [ -f "/etc/security/limits.conf" ]; then
        # Using limits.conf
        # Insert before the last line in the file
        preflight_actions+=('sed -i "\$i#Added by LUG-Helper:" /etc/security/limits.conf; sed -i "\$i* hard nofile 524288" /etc/security/limits.conf')
        preflight_fix_results+=("The open files limit configuration has been appended to:\n/etc/security/limits.conf")
    else
        # Don't know what method to use
        preflight_fix_results+=("This Helper is unable to detect the correct method of setting\nthe open file descriptors limit on your system.\n\nWe recommend manually configuring this limit to at least 524288.")
    fi

    # Verify that setting the limit was successful
    preflight_followup+=("filelimit_confirm")
}

# Check if setting the open file descriptors limit was successful
filelimit_confirm() {
    if [ "$(ulimit -Hn)" -lt 524288 ]; then
        preflight_fix_results+=("WARNING: As far as this Helper can detect, the open files limit\nwas not successfully configured on your system.\nYou may experience crashes.")
    fi
}

############################################################################
######## end filelimit functions ###########################################
############################################################################

############################################################################
######## end preflight check functions #####################################
############################################################################

############################################################################
######## begin download functions ##########################################
############################################################################

# Manage downloads. Called by a dedicated download type manage function, ie runner_manage_lutris()
#
# This function expects the following variables to be set:
#
# - The string download_sources is a formatted array containing the URLs
#   of items to download. It should be pointed to the appropriate
#   array set at the top of the script using indirect expansion.
#   See runner_sources at the top and runner_manage_lutris() for examples.
# - The array download_dirs should contain the locations the downloaded item
#   will be installed to. Must be formatted in pairs of ("[type]" "[directory]")
# - The string "download_menu_heading" should contain the type of item
#   being downloaded.  It will appear in the menu heading.
# - The string "download_menu_description" should contain a description of
#   the item being downloaded.  It will appear in the menu subheading.
# - The integer "download_menu_height" specifies the height of the zenity menu.
#
# This function also expects one string argument containing the type of item to
# be downloaded.  ie. runner or dxvk.
#
# See runner_manage_lutris() for a configuration example.
download_manage() {
    # This function expects a string to be passed as an argument
    if [ -z "$1" ]; then
        debug_print exit "Script error:  The download_manage function expects a string argument. Aborting."
    fi

    # Sanity checks
    if [ -z "$download_sources" ]; then
        debug_print exit "Script error: The string 'download_sources' was not set before calling the download_manage function. Aborting."
    elif [ "${#download_dirs[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'download_dirs' was not set before calling the download_manage function. Aborting."
    elif [ -z "$download_menu_heading" ]; then
        debug_print exit "Script error: The string 'download_menu_heading' was not set before calling the download_manage function. Aborting."
    elif [ -z "$download_menu_description" ]; then
        debug_print exit "Script error: The string 'download_menu_description' was not set before calling the download_manage function. Aborting."
    elif [ -z "$download_menu_height" ]; then
        debug_print exit "Script error: The string 'download_menu_height' was not set before calling the download_manage function. Aborting."
    fi

    # Get the type of item we're downloading from the function arguments
    download_type="$1"

    # The download management menu will loop until the user cancels
    looping_menu="true"
    while [ "$looping_menu" = "true" ]; do
        # Configure the menu
        menu_text_zenity="<b><big>Manage Your $download_menu_heading</big>\n\n$download_menu_description</b>\n\nYou may choose from the following options:"
        menu_text_terminal="Manage Your $download_menu_heading\n\n$download_menu_description\nYou may choose from the following options:"
        menu_text_height="$download_menu_height"
        menu_type="radiolist"

        # Configure the menu options
        delete="Remove an installed $download_type"
        back="Return to the main menu"
        unset menu_options
        unset menu_actions

        # Initialize success
        unset download_action_success

        # Loop through the download_sources array and create a menu item
        # for each one. Even numbered elements will contain the item name
        for (( i=0; i<"${#download_sources[@]}"; i=i+2 )); do
            # Set the options to be displayed in the menu
            menu_options+=("Install a $download_type from ${download_sources[i]}")
            # Set the corresponding functions to be called for each of the options
            menu_actions+=("download_select_install $i")
        done

        # Complete the menu by adding options to uninstall an item
        # or go back to the previous menu
        menu_options+=("$delete" "$back")
        menu_actions+=("download_select_delete" "menu_loop_done")

        # Calculate the total height the menu should be
        # menu_option_height = pixels per menu option
        # #menu_options[@] = number of menu options
        # menu_text_height = height of the title/description text
        # menu_text_height_zenity4 = added title/description height for libadwaita bigness
        menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"

        # Set the label for the cancel button
        cancel_label="Go Back"

        # Call the menu function.  It will use the options as configured above
        menu

        # Perform post-download actions and display messages or instructions
        if [ -n "$download_action_success" ] && [ "$post_download_type" != "none" ]; then
            post_download
        fi
    done
}

# Configure the download_manage function for non-Lutris wine runners
runner_manage_wine() {
    # We'll want to instruct the user on how to use the downloaded runner
    # Valid options are "none", "info", "configure-lutris", or "configure-wine"
    post_download_type="configure-wine"

    # Use indirect expansion to point download_sources
    # to the runner_sources array set at the top of the script
    declare -n download_sources=runner_sources

    # Get directories so we know where the wine prefix is
    getdirs

    # Set the download directory for wine runners
    # Unlike Lutris, only installting to one directory is supported
    # Do not include multiple download destinations in this array
    # Must be formatted in pairs of ("[type]" "[directory]")
    download_dirs=("wine" "$wine_prefix/runners")

    # Configure the text displayed in the menus
    download_menu_heading="Wine Runners (non-Lutris)"
    download_menu_description="The runners listed below are wine builds created for Star Citizen"
    download_menu_height="140"

    # Configure the post install and delete messages
    # Format:
    # post_install_msg is displayed below the header
    # post_delete_msg is displayed with no header
    post_install_msg_heading="Download Complete"
    post_install_msg="The launch script needs to be updated\n\nWould you like to automatically configure it to use this runner?"
    post_delete_msg="The launch script needs to be updated\n\nWould you like to automatically revert to using your system wine?"
    # Set the string sed will match against when editing the launch script
    # This will be used to detect the appropriate variable and replace its value
    # with the path to the downloaded item
    post_download_sed_string="export wine_path="
    # Set the value of the above variable that will be restored after a runner is deleted
    # In this case, we want to revert to calling system wine
    post_delete_restore_value="$(command -v wine | xargs dirname)"

    # Call the download_manage function with the above configuration
    # The argument passed to the function is used for special handling
    # and displayed in the menus and dialogs.
    download_manage "runner"
}

# Configure the download_manage function for Lutris runners
runner_manage_lutris() {
    # Lutris will need to be configured and restarted after modifying runners
    # Valid options are "none", "info", "configure-lutris", or "configure-wine"
    post_download_type="configure-lutris"

    # Use indirect expansion to point download_sources
    # to the runner_sources array set at the top of the script
    declare -n download_sources=runner_sources

    # Check if Lutris is installed and get relevant directories
    get_lutris_dirs "runner"
    if [ "$lutris_installed" = "false" ]; then
        message warning "Lutris is required but does not appear to be installed."
        return 0
    fi
    # Point download_dirs to the lutris_dirs array set by get_lutris_dirs
    # Must be formatted in pairs of ("[type]" "[directory]")
    declare -n download_dirs=lutris_dirs

    # Configure the text displayed in the menus
    download_menu_heading="Lutris Runners"
    download_menu_description="The runners listed below are wine builds created for Star Citizen"
    download_menu_height="140"

    # Configure the post install and delete messages
    # Format:
    # post_install_msg is displayed below the header
    # post_delete_msg is displayed with no header
    post_install_msg_heading="Download Complete"
    post_install_msg="Would you like to automatically configure Lutris to use this runner?\n\nLutris will be restarted if necessary."
    post_delete_msg="Lutris must be restarted to detect the changes.\nWould you like this Helper to restart it for you?"
    # Set the string sed will match against when editing Lutris yml configs
    # This will be used to detect the appropriate yml key and replace its value
    # with the name of the downloaded item
    post_download_sed_string="version: "

    # Call the download_manage function with the above configuration
    # The argument passed to the function is used for special handling
    # and displayed in the menus and dialogs.
    download_manage "runner"
}

# Configure the download_manage function for Lutris dxvks
dxvk_manage_lutris() {
    # Lutris will need to be configured and restarted after modifying dxvks
    # Valid options are "none", "info", "configure-lutris", or "configure-wine"
    post_download_type="configure-lutris"

    # Use indirect expansion to point download_sources
    # to the dxvk_sources array set at the top of the script
    declare -n download_sources=dxvk_sources

    # Check if Lutris is installed and get relevant directories
    get_lutris_dirs "dxvk"
    if [ "$lutris_installed" = "false" ]; then
        message warning "Lutris is required but does not appear to be installed."
        return 0
    fi
    # Point download_dirs to the lutris_dirs array set by get_lutris_dirs
    # Must be formatted in pairs of ("[type]" "[directory]")
    declare -n download_dirs=lutris_dirs

    # Configure the text displayed in the menus
    download_menu_heading="Lutris DXVK Versions"
    download_menu_description="The DXVK versions below may improve performance"
    download_menu_height="140"

    # Configure the post install and delete messages
    # Format:
    # post_install_msg is displayed below the header
    # post_delete_msg is displayed with no header
    post_install_msg_heading="Download Complete"
    post_install_msg="Would you like to automatically configure Lutris to use this DXVK?\n\nLutris will be restarted if necessary."
    post_delete_msg="Lutris must be restarted to detect the changes.\nWould you like this Helper to restart it for you?"
    # Set the string sed will match against when editing Lutris yml configs
    # This will be used to detect the appropriate yml key and replace its value
    # with the name of the downloaded item
    post_download_sed_string="dxvk_version: "

    # Call the download_manage function with the above configuration
    # The argument passed to the function is used for special handling
    # and displayed in the menus and dialogs.
    download_manage "dxvk"
}

# List available items for download. Called by download_manage()
#
# The following variables are expected to be set before calling this function:
# - download_sources (array)
# - download_type (string)
# - download_dirs (array)
download_select_install() {
    # This function expects an element number for the sources array to be passed in as an argument
    if [ -z "$1" ]; then
        debug_print exit "Script error:  The download_select_install function expects a numerical argument. Aborting."
    fi

    # Sanity checks
    if [ "${#download_sources[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'download_sources' was not set before calling the download_select_install function. Aborting."
    elif [ -z "$download_type" ]; then
        debug_print exit "Script error: The string 'download_type' was not set before calling the download_select_install function. Aborting."
    elif [ "${#download_dirs[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'download_dirs' was not set before calling the download_select_install function. Aborting."
    fi

    # Store info from the selected contributor
    contributor_name="${download_sources[$1]}"
    contributor_url="${download_sources[$1+1]}"

    # For runners, check GlibC version against runner requirements
    if [ "$download_type" = "runner" ] && { [ "$contributor_name" = "/dev/null" ] || [ "$contributor_name" = "TKG" ]; }; then
        unset glibc_fail
        required_glibc="2.33"

        # Native lutris
        if [ "$lutris_native" = "true" ]; then
            if [ -x "$(command -v ldd)" ]; then
                native_glibc="$(ldd --version | awk '/ldd/{print $NF}')"
            else
                native_glibc="0 (Not installed)"
            fi

            # Sort the versions and check if the installed glibc is smaller
            if [ "$required_glibc" != "$native_glibc" ] &&
            [ "$native_glibc" = "$(printf "%s\n%s" "$native_glibc" "$required_glibc" | sort -V | head -n1)" ]; then
                glibc_fail+=("Native")
            fi
        fi

        # Flatpak lutris
        if [ "$lutris_flatpak" = "true" ]; then
            flatpak_glibc="$(flatpak run --command="ldd" net.lutris.Lutris --version | awk '/ldd/{print $NF}')"

            # Sort the versions and check if the installed glibc is smaller
            if [ "$required_glibc" != "$flatpak_glibc" ] &&
            [ "$flatpak_glibc" = "$(printf "%s\n%s" "$flatpak_glibc" "$required_glibc" | sort -V | head -n1)" ]; then
                glibc_fail+=("Flatpak")
            fi
        fi

        # Display a warning message
        if [ "${#glibc_fail[@]}" -gt 0 ]; then
            unset glibc_message
            # Prepare the warning message
            for (( i=0; i<"${#glibc_fail[@]}"; i++ )); do
                case "${glibc_fail[i]}" in
                    "Native")
                        glibc_message+="System glibc: $native_glibc\n"
                        ;;
                    "Flatpak")
                        glibc_message+="Flatpak glibc: $flatpak_glibc\n"
                        ;;
                    *)
                        debug_print exit "Script error:  Unknown glibc_fail string in download_select_install() function. Aborting."
                        ;;
                esac
            done

            message warning "Your glibc version is incompatible with the selected runner\n\n${glibc_message}Minimum required glibc: $required_glibc"

            # Return if all installed versions of lutris fail the check
            if [ "$lutris_native" = "true" ] && [ "$lutris_flatpak" = "true" ]; then
                # Both are installed
                if [ "${#glibc_fail[@]}" -eq 2 ]; then
                    # Both failed the check
                    return 1
                fi
            else
                # Only one is installed, but it failed the check
                return 1
            fi
        fi
    fi

    # Check the provided contributor url to make sure we know how to handle it
    # To add new sources, add them here and handle in the if statement
    # just below and in the download_install function
    case "$contributor_url" in
        https://api.github.com/*)
            download_url_type="github"
            ;;
        https://gitlab.com/api/v4/projects/*)
            download_url_type="gitlab"
            ;;
        *)
            debug_print exit "Script error:  Unknown api/url format in ${download_type}_sources array. Aborting."
            ;;
    esac

    # Set the search keys we'll use to parse the api for the download url
    # To add new sources, handle them here, in the if statement
    # just above, and in the download_install function
    if [ "$download_url_type" = "github" ]; then
        # Which json key are we looking for?
        search_key="browser_download_url"
        # Optional: Only match urls containing a keyword
        match_url_keyword=""
        # Optional: Filter out game-specific builds by keyword
        # Format for grep extended regex (ie: "word1|word2|word3")
        if [ "$download_type" = "runner" ] && [ "$contributor_name" = "GloriousEggroll" ]; then
            filter_keywords="lol|diablo"
        elif [ "$download_type" = "runner" ] && [ "$contributor_name" = "Kron4ek" ]; then
            filter_keywords="x86|wow64"
        else
            filter_keywords="oh hi there. this is just placeholder text. how are you today?"
        fi
        # Add a query string to the url
        query_string="?per_page=$max_download_items"
    elif [ "$download_url_type" = "gitlab" ]; then
        # Which json key are we looking for?
        search_key="direct_asset_url"
        # Only match urls containing a keyword
        match_url_keyword="releases"
        # Optional: Filter out game-specific builds by keyword
        # Format for grep extended regex (ie: "word1|word2|word3")
        filter_keywords="oh hi there. this is just placeholder text. how are you today?"
        # Add a query string to the url
        query_string="?per_page=$max_download_items"
    else
        debug_print exit "Script error:  Unknown api/url format in ${download_type}_sources array. Aborting."
    fi

    # Fetch a list of versions from the selected contributor
    unset download_versions
    while IFS='' read -r line; do
        download_versions+=("$line")
    done < <(curl -s "$contributor_url$query_string" | grep -Eo "\"$search_key\": ?\"[^\"]+\"" | grep "$match_url_keyword" | cut -d '"' -f4 | cut -d '?' -f1 | xargs basename -a | grep -viE "$filter_keywords")
    # Note: match from search_key until " or EOL (Handles embedded commas and escaped quotes). Cut out quotes and gitlab's extraneous query strings.

    # Sanity check
    if [ "${#download_versions[@]}" -eq 0 ]; then
        message warning "No $download_type versions were found.  The source API may be down or rate limited."
        return 1
    fi

    # Configure the menu
    menu_text_zenity="Select the $download_type you want to install:"
    menu_text_terminal="Select the $download_type you want to install:"
    menu_text_height="60"
    menu_type="radiolist"
    goback="Return to the $download_type management menu"
    unset menu_options
    unset menu_actions

    # Iterate through the versions, check if they are installed,
    # and add them to the menu options
    # To add new file extensions, handle them here and in
    # the download_install function
    for (( i=0,num_download_items=0; i<"${#download_versions[@]}" && "$num_download_items"<"$max_download_items"; i++ )); do

        # Get the file name minus the extension
        case "${download_versions[i]}" in
            *.sha*sum | *.ini | proton* | *.txt)
                # Ignore hashes, configs, and proton downloads
                continue
                ;;
            *.tar.gz)
                download_basename="$(basename "${download_versions[i]}" .tar.gz)"
                ;;
            *.tgz)
                download_basename="$(basename "${download_versions[i]}" .tgz)"
                ;;
            *.tar.xz)
                download_basename="$(basename "${download_versions[i]}" .tar.xz)"
                ;;
            *.tar.zst)
                download_basename="$(basename "${download_versions[i]}" .tar.zst)"
                ;;
            *)
                # Print a warning and move on to the next item
                debug_print continue "Warning: Unknown archive filetype in download_select_install() function. Offending String: ${download_versions[i]}"
                continue
                ;;
        esac

        # Create a list of locations where the file is already installed
        unset installed_types
        for (( j=0; j<"${#download_dirs[@]}"; j=j+2 )); do
            # Loop through all download destinations to get installed types
            # Even numbered elements will contain the download destination type (ie. native/flatpak)
            if [ -d "${download_dirs[j+1]}/$download_basename" ]; then
                installed_types+=("${download_dirs[j]}")
            fi
        done

        # Build the menu item
        unset menu_option_text
        if [ "${#download_dirs[@]}" -eq 2 ]; then
            # We're only installing to one location
            if [ -d "${download_dirs[1]}/$download_basename" ]; then
                menu_option_text="$download_basename    [installed]"
            else
                # The file is not installed
                menu_option_text="$download_basename"
            fi
        else
            # We're installing to multiple locations
            if [ "${#installed_types[@]}" -gt 0 ]; then
                # The file is already installed
                menu_option_text="$download_basename    [installed:"
                for (( j=0; j<"${#installed_types[@]}"; j++ )); do
                    # Add labels for each installed location
                    menu_option_text="$menu_option_text ${installed_types[j]}"
                done
                # Complete the menu text
                menu_option_text="$menu_option_text]"
            else
                # The file is not installed
                menu_option_text="$download_basename"
            fi
        fi
        # Add the file names to the menu
        menu_options+=("$menu_option_text")
        menu_actions+=("download_install $i")

        # Increment the added items counter
        num_download_items="$(($num_download_items+1))"
    done

    # Complete the menu by adding the option to go back to the previous menu
    menu_options+=("$goback")
    menu_actions+=(":") # no-op

    # Calculate the total height the menu should be
    # menu_option_height = pixels per menu option
    # #menu_options[@] = number of menu options
    # menu_text_height = height of the title/description text
    # menu_text_height_zenity4 = added title/description height for libadwaita bigness
    menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"
    # Cap menu height
    if [ "$menu_height" -gt "$menu_height_max" ]; then
        menu_height="$menu_height_max"
    fi

    # Set the label for the cancel button
    cancel_label="Go Back"

    # Call the menu function.  It will use the options as configured above
    menu
}

# Download and install the selected item. Called by download_select_install()
#
# The following variables are expected to be set before calling this function:
# - download_versions (array)
# - contributor_url (string)
# - download_url_type (string)
# - download_type (string)
# - download_dirs (array)
download_install() {
    # This function expects an index number for the array
    # download_versions to be passed in as an argument
    if [ -z "$1" ]; then
        debug_print exit "Script error:  The download_install function expects a numerical argument. Aborting."
    fi

    # Sanity checks
    if [ "${#download_versions[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'download_versions' was not set before calling the download_install function. Aborting."
    elif [ -z "$contributor_url" ]; then
        debug_print exit "Script error: The string 'contributor_url' was not set before calling the download_install function. Aborting."
    elif [ -z "$download_url_type" ]; then
        debug_print exit "Script error: The string 'download_url_type' was not set before calling the download_install function. Aborting."
    elif [ -z "$download_type" ]; then
        debug_print exit "Script error: The string 'download_type' was not set before calling the download_install function. Aborting."
    elif [ "${#download_dirs[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'download_dirs' was not set before calling the download_install function. Aborting."
    fi

    # Get the filename including file extension
    download_filename="${download_versions[$1]}"

    # Get the selected item name minus the file extension
    # To add new file extensions, handle them here and in
    # the download_select_install function
    case "$download_filename" in
        *.tar.gz)
            download_basename="$(basename "$download_filename" .tar.gz)"
            ;;
        *.tgz)
            download_basename="$(basename "$download_filename" .tgz)"
            ;;
        *.tar.xz)
            download_basename="$(basename "$download_filename" .tar.xz)"
            ;;
        *.tar.zst)
            download_basename="$(basename "$download_filename" .tar.zst)"
            ;;
        *)
            debug_print exit "Script error: Unknown archive filetype in download_install function. Aborting."
            ;;
    esac

    # Set the search keys we'll use to parse the api for the download url
    # To add new sources, handle them here and in the
    # download_select_install function
    if [ "$download_url_type" = "github" ]; then
        # Which json key are we looking for?
        search_key="browser_download_url"
        # Add a query string to the url
        query_string="?per_page=$max_download_items"
    elif [ "$download_url_type" = "gitlab" ]; then
        # Which json key are we looking for?
        search_key="direct_asset_url"
        # Add a query string to the url
        query_string="?per_page=$max_download_items"
    else
        debug_print exit "Script error:  Unknown api/url format in ${download_type}_sources array. Aborting."
    fi

    # Get the selected download url
    download_url="$(curl -s "$contributor_url$query_string" | grep -Eo "\"$search_key\": ?\"[^\"]+\"" | grep "$download_filename" | cut -d '"' -f4 | cut -d '?' -f1 | sed 's|/-/blob/|/-/raw/|')"

    # Sanity check
    if [ -z "$download_url" ]; then
        message warning "Could not find the requested ${download_type}.  The source API may be down or rate limited."
        return 1
    fi

    # Download the item to the tmp directory
    download_file "$download_url" "$download_filename" "$download_type"

    # Sanity check
    if [ ! -f "$tmp_dir/$download_filename" ]; then
        # Something went wrong with the download and the file doesn't exist
        message error "Something went wrong and the requested $download_type file could not be downloaded!"
        debug_print continue "Download failed! File not found: $tmp_dir/$download_filename"
        return 1
    fi

    # Extract the archive to the tmp directory
    debug_print continue "Extracting $download_type into $tmp_dir/$download_basename..."
    if [ "$use_zenity" -eq 1 ]; then
        # Use Zenity progress bar
        mkdir "$tmp_dir/$download_basename" && tar -xf "$tmp_dir/$download_filename" -C "$tmp_dir/$download_basename" | \
                zenity --progress --pulsate --no-cancel --auto-close --title="Star Citizen LUG Helper" --text="Extracting ${download_type}...\n" 2>/dev/null
    else
        mkdir "$tmp_dir/$download_basename" && tar -xf "$tmp_dir/$download_filename" -C "$tmp_dir/$download_basename"
    fi

    # Check the contents of the extracted archive to determine the
    # directory structure we must create upon installation
    num_dirs=0
    num_files=0
    for extracted_item in "$tmp_dir/$download_basename"/*; do
        if [ -d "$extracted_item" ]; then
            num_dirs="$(($num_dirs+1))"
            extracted_dir="$(basename "$extracted_item")"
        elif [ -f "$extracted_item" ]; then
            num_files="$(($num_files+1))"
        fi
    done

    # Create the correct directory structure and install the item
    if [ "$num_dirs" -eq 0 ] && [ "$num_files" -eq 0 ]; then
        # Sanity check
        message warning "The downloaded archive is empty. There is nothing to do."
    elif [ "$num_dirs" -eq 1 ] && [ "$num_files" -eq 0 ]; then
        # If the archive contains only one directory, install that directory
        # We rename it to the name of the archive in case it is different
        # so we can easily detect installed items in download_select_install()
        for (( i=1; i<"${#download_dirs[@]}"; i=i+2 )); do
            # Loop through all download destinations, installing to each one
            # Odd numbered elements will contain the download destination's path
            if [ -d "${download_dirs[i]}/$download_basename" ]; then
                # This item has already been installed. Delete it before reinstalling
                debug_print continue "$download_type exists, deleting ${download_dirs[i]}/$download_basename..."
                rm -r --interactive=never "${download_dirs[i]:?}/$download_basename"
                debug_print continue "Reinstalling $download_type into ${download_dirs[i]}/$download_basename..."
            else
                debug_print continue "Installing $download_type into ${download_dirs[i]}/$download_basename..."
            fi
            if [ "$use_zenity" -eq 1 ]; then
                # Use Zenity progress bar
                mkdir -p "${download_dirs[i]}" && cp -r "$tmp_dir/$download_basename/$extracted_dir" "${download_dirs[i]}/$download_basename" | \
                        zenity --progress --pulsate --no-cancel --auto-close --title="Star Citizen LUG Helper" --text="Installing ${download_type}...\n" 2>/dev/null
            else
                mkdir -p "${download_dirs[i]}" && cp -r "$tmp_dir/$download_basename/$extracted_dir" "${download_dirs[i]}/$download_basename"
            fi
        done

        # Store the final name of the downloaded item
        downloaded_item_name="$download_basename"
        # Mark success for triggering post-download actions
        download_action_success="installed"
    elif [ "$num_dirs" -gt 1 ] || [ "$num_files" -gt 0 ]; then
        # If the archive contains more than one directory or
        # one or more files, we must create a subdirectory
        for (( i=1; i<"${#download_dirs[@]}"; i=i+2 )); do
            # Loop through all download destinations, installing to each one
            # Odd numbered elements will contain the download destination's path
            if [ -d "${download_dirs[i]}/$download_basename" ]; then
                # This item has already been installed. Delete it before reinstalling
                debug_print continue "$download_type exists, deleting ${download_dirs[i]}/$download_basename..."
                rm -r --interactive=never "${download_dirs[i]:?}/$download_basename"
                debug_print continue "Reinstalling $download_type into ${download_dirs[i]}/$download_basename..."
            else
                debug_print continue "Installing $download_type into ${download_dirs[i]}/$download_basename..."
            fi
            if [ "$use_zenity" -eq 1 ]; then
                # Use Zenity progress bar
                mkdir -p "${download_dirs[i]}/$download_basename" && cp -r "$tmp_dir"/"$download_basename"/* "${download_dirs[i]}"/"$download_basename" | \
                        zenity --progress --pulsate --no-cancel --auto-close --title="Star Citizen LUG Helper" --text="Installing ${download_type}...\n" 2>/dev/null
            else
                mkdir -p "${download_dirs[i]}/$download_basename" && cp -r "$tmp_dir"/"$download_basename"/* "${download_dirs[i]}"/"$download_basename"
            fi
        done

        # Store the final name of the downloaded item
        downloaded_item_name="$download_basename"
        # Mark success for triggering post-download actions
        download_action_success="installed"
    else
        # Some unexpected combination of directories and files
        debug_print exit "Script error:  Unexpected archive contents in download_install function. Aborting"
    fi

    # Cleanup tmp download
    debug_print continue "Cleaning up $tmp_dir/$download_filename..."
    rm --interactive=never "${tmp_dir:?}/$download_filename"
    rm -r --interactive=never "${tmp_dir:?}/$download_basename"

    return 0
}

# List installed items for deletion. Called by download_manage()
#
# The following variables are expected to be set before calling this function:
# - download_type (string)
# - download_dirs (array)
download_select_delete() {
    # Sanity checks
    if [ -z "$download_type" ]; then
        debug_print exit "Script error: The string 'download_type' was not set before calling the download_select_delete function. Aborting."
    elif [ "${#download_dirs[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'download_dirs' was not set before calling the download_select_delete function. Aborting."
    fi

    # Configure the menu
    menu_text_zenity="Select the $download_type(s) you want to remove:"
    menu_text_terminal="Select the $download_type you want to remove:"
    menu_text_height="60"
    menu_type="checklist"
    goback="Return to the $download_type management menu"
    unset installed_items
    unset installed_item_names
    unset menu_options
    unset menu_actions

    # Find all installed items in the download destinations
    for (( i=1; i<"${#download_dirs[@]}"; i=i+2 )); do
        # Skip if the directory doesn't exist
        if [ ! -d "${download_dirs[i]}" ]; then
            continue
        fi
        # Loop through all download destinations
        # Odd numbered elements will contain the download destination's path
        for item in "${download_dirs[i]}"/*; do
            if [ -d "$item" ]; then
                if [ "${#download_dirs[@]}" -eq 2 ]; then
                    # We're deleting from one location
                    installed_item_names+=("$(basename "$item")")
                else
                    # We're deleting from multiple locations so label each one
                    installed_item_names+=("$(basename "$item    [${download_dirs[i-1]}]")")
                fi
                installed_items+=("$item")
            fi
        done
    done

    # Create menu options for the installed items
    for (( i=0; i<"${#installed_items[@]}"; i++ )); do
        menu_options+=("${installed_item_names[i]}")
        menu_actions+=("download_delete $i")
    done

    # Print a message and return if no installed items were found
    if [ "${#menu_options[@]}" -eq 0 ]; then
        message info "No installed ${download_type}s found."
        return 0
    fi

    # Complete the menu by adding the option to go back to the previous menu
    menu_options+=("$goback")
    menu_actions+=(":") # no-op

    # Calculate the total height the menu should be
    # menu_option_height = pixels per menu option
    # #menu_options[@] = number of menu options
    # menu_text_height = height of the title/description text
    # menu_text_height_zenity4 = added title/description height for libadwaita bigness
    menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"
    # Cap menu height
    if [ "$menu_height" -gt "$menu_height_max" ]; then
        menu_height="$menu_height_max"
    fi

    # Set the label for the cancel button
    cancel_label="Go Back"

    # Call the menu function.  It will use the options as configured above
    menu
}

# Uninstall the selected item(s). Called by download_select_install()
# Accepts array index numbers as an argument
#
# The following variables are expected to be set before calling this function:
# - download_type (string)
# - installed_items (array)
# - installed_item_names (array)
download_delete() {
    # This function expects at least one index number for the array installed_items to be passed in as an argument
    if [ -z "$1" ]; then
        debug_print exit "Script error:  The download_delete function expects an argument. Aborting."
    fi

    # Sanity checks
    if [ -z "$download_type" ]; then
        debug_print exit "Script error: The string 'download_type' was not set before calling the download_delete function. Aborting."
    elif [ "${#installed_items[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'installed_items' was not set before calling the download_delete function. Aborting."
    elif [ "${#installed_item_names[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'installed_item_names' was not set before calling the download_delete function. Aborting."
    fi

    # Capture arguments and format a list of items
    item_to_delete=("$@")
    unset list_to_delete
    unset deleted_item_names
    for (( i=0; i<"${#item_to_delete[@]}"; i++ )); do
        list_to_delete+="\n${installed_items[${item_to_delete[i]}]}"
    done

    if message question "Are you sure you want to delete the following ${download_type}(s)?\n$list_to_delete"; then
        # Loop through the arguments
        for (( i=0; i<"${#item_to_delete[@]}"; i++ )); do
            rm -r --interactive=never "${installed_items[${item_to_delete[i]}]}"
            debug_print continue "Deleted ${installed_items[${item_to_delete[i]}]}"

            # Store the names of deleted items for post_download() processing
            deleted_item_names+=("${installed_item_names[${item_to_delete[i]}]}")
        done
        # Mark success for triggering post-deletion actions
        download_action_success="deleted"
    fi
}

# Perform post-download actions or display a message/instructions
#
# The following variables are expected to be set before calling this function:
# - post_download_type (string. "none", "info", "configure-lutris", "configure-wine")
# - post_install_msg_heading (string)
# - post_install_msg (string)
# - post_delete_msg (string)
# - post_download_sed_string (string. For types configure-lutris and configure-wine)
# - post_delete_restore_value (string. For type configure-wine)
# - download_action_success (string. Set automatically in install/delete functions)
# - downloaded_item_name (string. For installs only. Set automatically in download_install function)
# - deleted_item_names (array. For deletions only. Set automatically in download_delete function)
#
# Details for post_download_sed_string:
# This is the string sed will match against when editing Lutris yml configs
# It will be used to detect the appropriate yml key and replace its value
# with the name of the downloaded item. Example: "dxvk_version: "
#
# Message display format:
# A header is automatically displayed that reads: Download Complete
# post_install_msg is displayed below the header
post_download() {
    # Sanity checks
    if [ -z "$post_download_type" ]; then
        debug_print exit "Script error: The string 'post_download_type' was not set before calling the post_download function. Aborting."
    elif [ -z "$post_install_msg_heading" ]; then
        debug_print exit "Script error: The string 'post_install_msg_heading' was not set before calling the post_download function. Aborting."
    elif [ -z "$post_install_msg" ]; then
        debug_print exit "Script error: The string 'post_install_msg' was not set before calling the post_download function. Aborting."
    elif [ -z "$post_delete_msg" ]; then
        debug_print exit "Script error: The string 'post_delete_msg' was not set before calling the post_download function. Aborting."
    elif [ -z "$post_download_sed_string" ] && [ "$post_download_type" = "configure-lutris" ]; then
        debug_print exit "Script error: The string 'post_download_sed_string' was not set before calling the post_download function. Aborting."
    elif [ -z "$post_download_sed_string" ] && [ "$post_download_type" = "configure-wine" ]; then
        debug_print exit "Script error: The string 'post_download_sed_string' was not set before calling the post_download function. Aborting."
    elif [ -z "$post_delete_restore_value" ] && [ "$post_download_type" = "configure-wine" ]; then
        debug_print exit "Script error: The string 'post_delete_restore_value' was not set before calling the post_download function. Aborting."
    fi

    # Return if we don't have anything to do
    if [ "$post_download_type" = "none" ]; then
        return 0
    fi

    # Configure the message heading and format it for zenity
    if [ "$use_zenity" -eq 1 ]; then
        post_install_msg_heading="<b>$post_install_msg_heading</b>"
    fi

    # Display appropriate post-download message
    if [ "$post_download_type" = "info" ]; then
            # Just displaying an informational message
            message info "$post_install_msg_heading\n\n$post_install_msg"
    elif [ "$post_download_type" = "configure-lutris" ]; then
        # We need to configure and restart Lutris
        unset lutris_game_ymls
        # Build an array of all Lutris Star Citizen yml files
        while IFS='' read -r line; do
            lutris_game_ymls+=("$line")
        done < <(grep -iRlE --include="*.yml" "Roberts Space Industries|starcitizen|star citizen|star-citizen" "$lutris_native_conf_dir" "$lutris_flatpak_conf_dir" 2>/dev/null)

        # We handle installs and deletions differently
        if [ "$download_action_success" = "installed" ]; then
            # We are installing something for Lutris
            if message question "$post_install_msg_heading\n\n$post_install_msg"; then
                # Cylce through all Lutris config files for Star Citizen and configure the downloaded item
                for (( i=0; i<"${#lutris_game_ymls[@]}"; i++ )); do
                    # Replace the appropriate key:value line if it exists
                    sed -Ei "/^wine:/,/^[^[:blank:]]/ {/^[[:blank:]]*${post_download_sed_string}/s/${post_download_sed_string}.*/${post_download_sed_string}${downloaded_item_name}/}" "${lutris_game_ymls[i]}"

                    # If it doesn't exist, add it at the start of the wine: grouping
                    if ! grep -q "${post_download_sed_string}${downloaded_item_name}" "${lutris_game_ymls[i]}"; then
                        # This assumes an indent of two spaces before the key:value pair
                        sed -i -e '/^wine:/a\' -e "  ${post_download_sed_string}${downloaded_item_name}" "${lutris_game_ymls[i]}"
                    fi
                done

                # Lutris needs to be restarted after making changes
                if [ "$(pgrep -f lutris)" ]; then
                    # For installations, we ask the user if we can configure and restart Lutris in the post_install_msg
                    lutris_restart
                fi
            fi
        elif [ "$download_action_success" = "deleted" ]; then
            # Find all Star Citizen Lutris configs and delete the matching key:value line
            for (( i=0; i<"${#deleted_item_names[@]}"; i++ )); do
                # Cylce through all Lutris config files for Star Citizen and remove the item
                for (( j=0; j<"${#lutris_game_ymls[@]}"; j++ )); do
                    sed -Ei "/^wine:/,/^[^[:blank:]]/ {/${post_download_sed_string}${deleted_item_names[i]}/d}" "${lutris_game_ymls[j]}"
                done
            done

            # Lutris needs to be restarted after making changes
            if [ "$(pgrep -f lutris)" ] && message question "$post_delete_msg"; then
                # For deletions, we ask the user if it's okay to restart Lutris here
                lutris_restart
            fi
        else
            debug_print exit "Script error: Unknown download_action_success value in post_download function. Aborting."
        fi
    elif [ "$post_download_type" = "configure-wine" ]; then
        # We handle installs and deletions differently
        if [ "$download_action_success" = "installed" ]; then
            # We are installing a wine version and updating the launch script to use it
            if message question "$post_install_msg_heading\n\n$post_install_msg"; then
                # Make sure we can locate the launch script
                if [ ! -f "$wine_prefix/$wine_launch_script_name" ]; then
                    message error "Unable to find $wine_prefix/$wine_launch_script_name"
                    return 1
                fi
                # Make sure the launch script has the appropriate string to be replaced
                if ! grep -q "^${post_download_sed_string}" "$wine_prefix/$wine_launch_script_name"; then
                    message error "Unable to to find a required variable in\n$wine_prefix/$wine_launch_script_name\n\nYour launch script may be out of date and will need to be edited manually!"
                    return 1
                fi

                # Replace the specified variable
                sed -i "s|^${post_download_sed_string}.*|${post_download_sed_string}\"${wine_prefix}/runners/${downloaded_item_name}/bin\"|" "$wine_prefix/$wine_launch_script_name"
            else
                message warning "The launch script will need to be edited manually!\n\n$wine_prefix/$wine_launch_script_name"
            fi
        elif [ "$download_action_success" = "deleted" ]; then
            # We deleted a custom wine version and need to revert the launch script to use the system wine
            if message question "$post_delete_msg"; then
                # Make sure we can locate the launch script
                if [ ! -f "$wine_prefix/$wine_launch_script_name" ]; then
                    message error "Unable to find $wine_prefix/$wine_launch_script_name"
                    return 1
                fi
                # Make sure the launch script has the appropriate string to be replaced
                if ! grep -q "^${post_download_sed_string}" "$wine_prefix/$wine_launch_script_name"; then
                    message error "Unable to to find a required variable in\n$wine_prefix/$wine_launch_script_name\n\nYour launch script may be out of date and will need to be edited manually!"
                    return 1
                fi

                # Restore the specified variable
                sed -i "s#^${post_download_sed_string}.*#${post_download_sed_string}\"${post_delete_restore_value}\"#" "$wine_prefix/$wine_launch_script_name"
            else
                message warning "The launch script will need to be edited manually!\n\n$wine_prefix/$wine_launch_script_name"
            fi
        else
            debug_print exit "Script error: Unknown download_action_success value in post_download function. Aborting."
        fi
    else
            debug_print exit "Script error: Unknown post_download_type value in post_download function. Aborting."
    fi
}

# Create an array of directories used by Lutris
# Array will be formatted in pairs of ("[type]" "[directory]")
# Supports native install and flatpak
# Takes an argument to specify the type to return: "runner" or "dxvk"
get_lutris_dirs() {
    # Sanity check
    if [ "$#" -lt 1 ]; then
        debug_print exit "Script error: The get_lutris_dirs function expects one argument. Aborting."
    fi

    # Detect the type of Lutris install
    lutris_detect

    # Add lutris directories to an array
    unset lutris_dirs
    case "$1" in
        "runner")
            # Native Lutris install
            if [ "$lutris_native" = "true" ]; then
                lutris_dirs+=("native" "$runners_dir_native")
            fi
            # Flatpak lutris install
            if [ "$lutris_flatpak" = "true" ]; then
                lutris_dirs+=("flatpak" "$runners_dir_flatpak")
            fi
            ;;
        "dxvk")
            # Native Lutris install
            if [ "$lutris_native" = "true" ]; then
                lutris_dirs+=("native" "$dxvk_dir_native")
            fi
            # Flatpak lutris install
            if [ "$lutris_flatpak" = "true" ]; then
                lutris_dirs+=("flatpak" "$dxvk_dir_flatpak")
            fi
            ;;
        *)
            printf "lug-helper.sh: Unknown argument provided to get_lutris_dirs function. Aborting.\n" 1>&2
            read -n 1 -s -p "Press any key..."
            exit 0
            ;;
    esac
}

# Detect which version of Lutris is running and restart it
lutris_restart() {
    # Detect the installed versions of Lutris
    lutris_detect
    if [ "$lutris_native" = "true" ] && pgrep -f lutris | xargs ps -fp | grep -Eq "[/]usr/bin/lutris|[/]usr/games/lutris"; then
        # Native Lutris is running
        debug_print continue "Restarting native Lutris..."
        pkill -f -SIGTERM lutris && nohup lutris </dev/null &>/dev/null &
    fi
    if [ "$lutris_flatpak" = "true" ] && pgrep -f lutris | xargs ps -fp | grep -q "[/]app/bin/lutris"; then
        # Flatpak Lutris is running
        debug_print continue "Restarting flatpak Lutris..."
        pkill -f -SIGTERM lutris && nohup flatpak run net.lutris.Lutris </dev/null &>/dev/null &
    fi
}

# Download a file to the tmp directory
# Expects three arguments: The download URL, file name, and download type
download_file() {
    # This function expects three string arguments
    if [ "$#" -lt 3 ]; then
        printf "\nScript error:  The download_file function expects three arguments. Aborting.\n"
        read -n 1 -s -p "Press any key..."
        exit 0
    fi

    # Capture the arguments and encode spaces in urls
    download_url="${1// /%20}"
    download_filename="$2"
    download_type="$3"

    # Download the item to the tmp directory
    debug_print continue "Downloading $download_url into $tmp_dir/$download_filename..."
    if [ "$use_zenity" -eq 1 ]; then
        # Format the curl progress bar for zenity
        mkfifo "$tmp_dir/lugpipe"
        cd "$tmp_dir" && curl -#L "$download_url" -o "$download_filename" > "$tmp_dir/lugpipe" 2>&1 & curlpid="$!"
        stdbuf -oL tr '\r' '\n' < "$tmp_dir/lugpipe" | \
        grep --line-buffered -ve "100" | grep --line-buffered -o "[0-9]*\.[0-9]" | \
        (
            trap 'kill "$curlpid"' ERR
            zenity --progress --auto-close --title="Star Citizen LUG Helper" --text="Downloading ${download_type}.  This might take a moment.\n" 2>/dev/null
        )

        if [ "$?" -eq 1 ]; then
            # User clicked cancel
            debug_print continue "Download aborted. Removing $tmp_dir/$download_filename..."
            rm --interactive=never "${tmp_dir:?}/$download_filename"
            rm --interactive=never "${tmp_dir:?}/lugpipe"
            return 1
        fi
        rm --interactive=never "${tmp_dir:?}/lugpipe"
    else
        # Standard curl progress bar
        (cd "$tmp_dir" && curl -#L "$download_url" -o "$download_filename")
    fi
}

############################################################################
######## end download functions ############################################
############################################################################

############################################################################
######## begin maintenance functions #######################################
############################################################################

# Show maintenance/troubleshooting options
maintenance_menu() {
    # Loop the menu until the user selects quit
    looping_menu="true"
    while [ "$looping_menu" = "true" ]; do
        # Fetch wine prefix
        if [ -f "$conf_dir/$conf_subdir/$wine_conf" ]; then
            maint_prefix="$(cat "$conf_dir/$conf_subdir/$wine_conf")"
        else
            maint_prefix="Not configured"
        fi

        # Configure the menu
        menu_text_zenity="<b><big>Game Maintenance and Troubleshooting</big>\n\nLUG Wiki: $lug_wiki\n\nWine prefix:</b> $maint_prefix"
        menu_text_terminal="Game Maintenance and Troubleshooting\n\nLUG Wiki: $lug_wiki\n\nWine prefix: $maint_prefix"
        menu_text_height="140"
        menu_type="radiolist"

        # Configure the menu options
        version_msg="Switch the Helper between LIVE/PTU/EPTU  (Currently: $game_version)"
        prefix_msg="Target a different Star Citizen installation"
        launcher_msg="Update game launch script (non-Lutris)"
        powershell_msg="Install PowerShell into Wine prefix"
        userdir_msg="Delete my user folder and preserve keybinds/characters"
        shaders_msg="Delete my shaders (Do this after each game update)"
        vidcache_msg="Delete my DXVK cache"
        eac_msg="Delete Easy Anti-Cheat Workaround"
        dirs_msg="Display Helper and Star Citizen directories"
        reset_msg="Reset Helper configs"
        quit_msg="Return to the main menu"

        # Set the options to be displayed in the menu
        menu_options=("$version_msg" "$prefix_msg" "$launcher_msg" "$powershell_msg" "$userdir_msg" "$shaders_msg" "$vidcache_msg" "$eac_msg" "$dirs_msg" "$reset_msg" "$quit_msg")
        # Set the corresponding functions to be called for each of the options
        menu_actions=("version_menu" "switch_prefix" "update_launcher" "install_powershell" "rm_userdir" "rm_shaders" "rm_dxvkcache" "rm_eac_workaround" "display_dirs" "reset_helper" "menu_loop_done")

        # Calculate the total height the menu should be
        # menu_option_height = pixels per menu option
        # #menu_options[@] = number of menu options
        # menu_text_height = height of the title/description text
        # menu_text_height_zenity4 = added title/description height for libadwaita bigness
        menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"

       # Set the label for the cancel button
       cancel_label="Go Back"

        # Call the menu function.  It will use the options as configured above
        menu
    done
}

# Display a menu to select the game version (LIVE/PTU/EPTU) to target for all Helper functions
version_menu(){
    # Configure the menu
    menu_text_zenity="Select the game version the Helper will target:"
    menu_text_terminal="Select the game version the Helper will target:"
    menu_text_height="60"
    menu_type="radiolist"
    goback="Cancel"

    # Set the options to be displayed in the menu
    menu_options=("LIVE" "PTU" "EPTU" "$goback")
    # Set the corresponding functions to be called for each of the options
    menu_actions=("set_version $live_dir" "set_version $ptu_dir" "set_version $eptu_dir" ":")

    # Calculate the total height the menu should be
    # menu_option_height = pixels per menu option
    # #menu_options[@] = number of menu options
    # menu_text_height = height of the title/description text
    # menu_text_height_zenity4 = added title/description height for libadwaita bigness
    menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"

    # Set the label for the cancel button
    cancel_label="Cancel"

    # Call the menu function.  It will use the options as configured above
    menu
}

# Set the game version to target for all Helper functions
# Accepts a string as an argument
set_version() {
    # This function expects a string to be passed in as an argument
    if [ -z "$1" ]; then
        debug_print exit "Script error:  The set_version function expects an argument. Aborting."
    fi

    # Set the game version from the passed argument
    game_version="$1"
}

# Target the Helper at a different Star Citizen prefix/installation
switch_prefix() {
    # Check if the config file exists
    if [ -f "$conf_dir/$conf_subdir/$wine_conf" ] && [ -f "$conf_dir/$conf_subdir/$game_conf" ]; then
        getdirs
        # Above will return code 3 if the user had to select new directories. This can happen if the stored directories are now invalid.
        # We check this so we don't prompt the user to set directories twice here.
        if [ "$?" -ne 3 ] && message question "The Helper is currently targeting this Star Citizen install\nWould you like to change it?\n\n$wine_prefix"; then
            reset_helper "switchprefix"
            # Prompt the user for a new set of game paths
            getdirs
        fi
    else
        # Prompt the user for game paths
        getdirs
    fi
}

# Update the non-Lutris game launch script if necessary
update_launcher() {
    getdirs

    if [ ! -f "$wine_prefix/$wine_launch_script_name" ]; then
        message warning "Game launch script not found! If you're using Lutris, you don't need to update this\n\n$wine_prefix/$wine_launch_script_name"
        return 1
    fi

    current_launcher_ver="$(grep "^# version:" "$wine_prefix/$wine_launch_script_name" | awk '{print $3}')"
    latest_launcher_ver="$(grep "^# version:" $wine_launch_script | awk '{print $3}')"

    if [ "$latest_launcher_ver" != "$current_launcher_ver" ] &&
       [ "$current_launcher_ver" = "$(printf "%s\n%s" "$current_launcher_ver" "$latest_launcher_ver" | sort -V | head -n1)" ]; then

        # Backup the file
        cp "$wine_prefix/$wine_launch_script_name" "$wine_prefix/$(basename "$wine_launch_script_name" .sh).bak"

        # Backup the variables we know we need
        bak_wineprefix="$(grep "^export WINEPREFIX=" "$wine_prefix/$wine_launch_script_name" | awk -F '=' '{print $2}')"
        bak_winepath="$(grep -e "^export wine_path=" -e "^wine_path=" "$wine_prefix/$wine_launch_script_name" | awk -F '=' '{print $2}')"

        # If wineprefix isn't found in the file, something is wrong and we shouldn't proceed
        if [ -z "$bak_wineprefix" ]; then
            message error "The WINEPREFIX env var was not found in your launch script. Unable to proceed!\n\n$wine_prefix/$wine_launch_script_name"
            return 1
        fi

        # If wine_path is empty, it may be an older version of the launch script. Default to system wine
        if [ -z "$bak_winepath" ]; then
            bak_winepath="$(command -v wine | xargs dirname)"
        fi

        # Copy in the new launch script
        cp "$wine_launch_script" "$wine_prefix"

        # Restore the variables
        sed -i "s|^export WINEPREFIX=.*|export WINEPREFIX=$bak_wineprefix|" "$wine_prefix/$wine_launch_script_name"
        sed -i "s#^export wine_path=.*#export wine_path=$bak_winepath#" "$wine_prefix/$wine_launch_script_name"

        message info "Your game launch script has been updated!\n\nIf you had customized your script, you'll need to re-add your changes.\nA backup was created at:\n\n$wine_prefix/$(basename "$wine_launch_script_name" .sh).bak"
    else
        message info "Your game launch script is already up to date!"
    fi
}

# Save exported keybinds, wipe the USER directory, and restore keybinds
rm_userdir() {
    # Prompt user to back up the current keybinds in the game
    message info "Before proceeding, please be sure you have exported your Star Citizen keybinds and characters from within the game.\n\nTo export keybinds, launch the game and go to:\nOptions->Keybindings->Control Profiles->Save Control Settings\n\nTo export your character, go to the character creator from the main menu and save it with a name.\n\nGo on; I'll wait."

    # Get/Set directory paths
    getdirs
    if [ "$?" -eq 1 ]; then
        # User cancelled and wants to return to the main menu
        # or there was an error
        return 0
    fi

    # Sanity check
    if [ ! -d "$user_dir" ]; then
        message warning "User directory not found. There is nothing to delete!\n\n$user_dir"
        return 0
    fi

    # Check for exported keybind files
    if [ ! -d "$keybinds_dir" ] || [ -z "$(ls -A "$keybinds_dir")" ]; then
        if message question "Warning: No exported keybindings found.\nContinuing will erase your existing keybinds!\n\nDo you want to continue anyway?"; then
            keybinds_exported=0
        else
            # User said no
            return 0
        fi
    else
        keybinds_exported=1
    fi

    # Check for saved custom character files
    if [ ! -d "$custom_characters_dir" ] || [ -z "$(ls -A "$custom_characters_dir")" ]; then
        if message question "Warning: No saved characters found.\nContinuing will erase your existing character!\n\nDo you want to continue anyway?"; then
            characters_exported=0
        else
            # User said no
            return 0
        fi
    else
        characters_exported=1
    fi

    if message question "The following directory will be deleted:\n\n$user_dir\n\nDo you want to proceed?"; then
        # Back up keybinds
        if [ "$keybinds_exported" -eq 1 ]; then
            debug_print continue "Backing up keybinds to $backup_path/keybinds..."
            mkdir -p "$backup_path/keybinds" && cp -r "$keybinds_dir/." "$backup_path/keybinds/"
        fi

        #Back up characters
        if [ "$characters_exported" -eq 1 ]; then
            debug_print continue "Backing up characters to $backup_path/CustomCharacters..."
            mkdir -p "$backup_path/CustomCharacters" && cp -r "$custom_characters_dir/." "$backup_path/CustomCharacters/"
        fi

        # Wipe the user directory
        debug_print continue "Wiping $user_dir..."
        rm -r --interactive=never "$user_dir"

        # Restore custom keybinds
        if [ "$keybinds_exported" -eq 1 ]; then
            debug_print continue "Restoring keybinds..."
            mkdir -p "$keybinds_dir" && cp -r "$backup_path/keybinds/." "$keybinds_dir/"
        fi

        # Restore custom characters
        if [ "$characters_exported" -eq 1 ]; then
            debug_print continue "Restoring custom characters..."
            mkdir -p "$custom_characters_dir" && cp -r "$backup_path/CustomCharacters/." "$custom_characters_dir/"
        fi

        message info "Your Star Citizen USER directory has been cleaned up!\n\nExported keybinds can be re-imported in-game from:\nOptions->Keybindings->Control Profiles\n\nSaved characters can be selected in the character creator"
    fi
}

# Delete the shaders directory
rm_shaders() {
    # Get/Set directory paths
    getdirs
    if [ "$?" -eq 1 ]; then
        # User cancelled and wants to return to the main menu, or error
        return 0
    fi

    # Loop through all possible shader directories
    for appdata_dir in "$shaders_dir"/*; do
        # Loop through the shaders subdir array
        for shaders_subdir in "${shaders_subdirs[@]}"; do
            if [ -d "$appdata_dir/$shaders_subdir" ]; then
                # If a shaders directory is found, delete it
                if message question "The following directory will be deleted:\n\n$appdata_dir/$shaders_subdir\n\nDo you want to proceed?"; then
                    debug_print continue "Deleting $appdata_dir/$shaders_subdir..."
                    rm -r --interactive=never "${appdata_dir:?}/$shaders_subdir"
                fi
            fi
        done
    done

    message info "Shader operations completed"
}

# Delete DXVK cache
rm_dxvkcache() {
    # Get/Set directory paths
    getdirs
    if [ "$?" -eq 1 ]; then
        # User cancelled and wants to return to the main menu
        # or there was an error
        return 0
    fi

    # Sanity check
    if [ ! -f "$dxvk_cache" ]; then
        message warning "Unable to find the DXVK cache file. There is nothing to delete!\n\n$dxvk_cache"
        return 0
    fi

    # Delete the cache file
    if message question "The following file will be deleted:\n\n$dxvk_cache\n\nDo you want to proceed?"; then
        debug_print continue "Deleting $dxvk_cache..."
        rm --interactive=never "$dxvk_cache"
        message info "Your DXVK cache has been deleted!"
    fi
}

rm_eac_workaround() {
    # Get/Set directory paths
    getdirs
    # Detect the type of Lutris install
    lutris_detect

    if [ "$?" -eq 1 ]; then
    # User cancelled and wants to return to the main menu
    # or there was an error
    return 0
    fi

    # Set the EAC directory path and hosts modification
    # eac_dir="$wine_prefix/drive_c/users/$USER/AppData/Roaming/EasyAntiCheat"
    eac_hosts="127.0.0.1 modules-cdn.eac-prod.on.epicgames.com"

    # Configure message variables
    eac_title="Remove Easy Anti-Cheat Workaround"
    eac_hosts_formatted="$eac_hosts"
    if [ "$use_zenity" -eq 1 ]; then
        eac_title="<b>$eac_title</b>"
        eac_hosts_formatted="<i>$eac_hosts_formatted</i>"
    fi

    remove_eac_hosts="false"
    # delete_eac_dir="false"
    if grep -q "^$eac_hosts" /etc/hosts; then
        # Hosts workaround is in place
        eac_message="$eac_title\n\nThe following entry will be removed from /etc/hosts:\n$eac_hosts_formatted"
        remove_eac_hosts="true"

        # Finish up the message
        eac_message="$eac_message\n\n\nDo you want to proceed?"

        if message question "$eac_message"; then
            # Apply the hosts workaround if needed
            if [ "$remove_eac_hosts" = "true" ]; then
                debug_print continue "Editing hosts file..."
                # Try to modify /etc/hosts as root
                try_exec "sed -i 's/$eac_hosts/#&/' /etc/hosts"
                if [ "$?" -eq 1 ]; then
                    message error "Authentication failed or there was an error modifying /etc/hosts.\nSee terminal for more information.\n\nReturning to main menu."
                    return 0
                fi
            fi

            message info "Easy Anti-Cheat hosts workaround has been removed!"
        fi
    else
        message info "Easy Anti-Cheat hosts workaround was not present!"
    fi

    if [ "$lutris_native" = "true" ]; then
        for item in $lutris_native_conf_dir/star-citizen-*; do
            if message question "Are you sure you want to remove the EAC workaround from $(basename -- $item)?"; then
                sed -i "/EOS_USE_ANTICHEATCLIENTNULL/d" "$item"
                sed -i "/SteamGameId/d" "$item"
            fi
        done
    fi

    if [ "$lutris_flatpak" = "true" ]; then
        for item in $lutris_flatpak_conf_dir/star-citizen-*; do
            if message question "Are you sure you want to remove the EAC workaround from $(basename -- $item)?"; then
                sed -i "/EOS_USE_ANTICHEATCLIENTNULL/d" "$item"
                sed -i "/SteamGameId/d" "$item"
            fi
        done
    fi

    if [ -f "$wine_prefix/$wine_launch_script_name" ]; then
        if message question "Are you sure you want to remove the EAC workaround from $wine_prefix/$wine_launch_script_name"; then
            sed -i "s/^export EOS_USE_ANTICHEATCLIENTNULL=1/#&/" "$wine_prefix/$wine_launch_script_name"

            message info "Easy Anti-Cheat Wine environment variable workaround has been removed!"
        fi
    fi
}

# Display all directories currently used by this helper and Star Citizen
display_dirs() {
    dirs_list="\n"
    lutris_detect

    # Helper configs and keybinds
    if [ -d "$conf_dir/$conf_subdir" ]; then
        dirs_list+="Helper configuration:\n$conf_dir/$conf_subdir\n\nKeybind backups:\n$conf_dir/$conf_subdir/keybinds\n\n"
    fi

    # Wine prefix
    if [ -f "$conf_dir/$conf_subdir/$wine_conf" ]; then
        dirs_list+="Wine prefix:\n$(cat "$conf_dir/$conf_subdir/$wine_conf")\n\n"
    fi

    # Star Citizen installation
    if [ -f "$conf_dir/$conf_subdir/$game_conf" ]; then
        dirs_list+="Star Citizen game directory:\n$(cat "$conf_dir/$conf_subdir/$game_conf")\n\n"
    fi

    # Star Citizen shaders path
    if [ -f "$conf_dir/$conf_subdir/$wine_conf" ]; then
        dirs_list+="Star Citizen shaders:\n$(cat "$conf_dir/$conf_subdir/$wine_conf")/$appdata_path\n\n"
    fi

    # Lutris runners
    if [ -d "$runners_dir_native" ] || [ -d "$runners_dir_flatpak" ]; then
        dirs_list+="Lutris Runners:"
        if [ -d "$runners_dir_native" ] && [ "$lutris_native" = "true" ]; then
            dirs_list+="\n$runners_dir_native"
        fi
        if [ -d "$runners_dir_flatpak" ] && [ "$lutris_flatpak" = "true" ]; then
            dirs_list+="\n$runners_dir_flatpak"
        fi
        dirs_list+="\n\n"
    fi

    # Lutris dxvk
    if [ -d "$dxvk_dir_native" ] || [ -d "$dxvk_dir_flatpak" ]; then
        dirs_list+="Lutris DXVK Versions:"
        if [ -d "$dxvk_dir_native" ] && [ "$lutris_native" = "true" ]; then
            dirs_list+="\n$dxvk_dir_native"
        fi
        if [ -d "$dxvk_dir_flatpak" ] && [ "$lutris_flatpak" = "true" ]; then
            dirs_list+="\n$dxvk_dir_flatpak"
        fi
        dirs_list+="\n\n"
    fi

    # Format the info header
    message_heading="These directories are currently being used by this Helper and Star Citizen"
    if [ "$use_zenity" -eq 1 ]; then
        message_heading="<b>$message_heading</b>"
    fi

    message info "$message_heading\n$dirs_list"
}

# Display the LUG Wiki
display_wiki() {
    # Display a message containing the URL
    message info "See the Wiki for our Quick-Start Guide, Troubleshooting,\nand Performance Tuning Recommendations:\n\n$lug_wiki"
}

# Delete the helper's config directory
reset_helper() {
    if [ "$1" = "switchprefix" ]; then
        # This gets called by the switch_prefix and install_game_wine functions
        # We only want to delete configs related to the game path in order to target a different game install
        debug_print continue "Deleting $conf_dir/$conf_subdir/{$wine_conf,$game_conf}..."
        rm --interactive=never "${conf_dir:?}/$conf_subdir/"{"$wine_conf","$game_conf"}
    elif message question "All config files will be deleted from:\n\n$conf_dir/$conf_subdir\n\nDo you want to proceed?"; then
        # Called normally by the user, wipe all the things!
        debug_print continue "Deleting $conf_dir/$conf_subdir/*.conf..."
        rm --interactive=never "${conf_dir:?}/$conf_subdir/"*.conf
        message info "The Helper has been reset!"
    fi
    # Also wipe path variables so the reset takes immediate effect
    wine_prefix=""
    game_path=""
}

############################################################################
######## end maintenance functions #########################################
############################################################################


# Install Star Citizen using Lutris
install_game_lutris() {
    # Check if Lutris is installed
    lutris_detect
    if [ "$lutris_installed" = "false" ]; then
        message error "Lutris is required but does not appear to be installed."
        return 1
    fi
    # Check if the install script exists
    if [ ! -f "$lutris_install_script" ]; then
        message error "Lutris install script not found! Unable to proceed.\n\n$lutris_install_script\n\nIt is included in our official releases here:\n$releases_url"
        return 1
    fi

    # Call the preflight check
    preflight_check "lutris"
    if [ "$?" -eq 1 ]; then
        # There were errors
        install_question="Before proceeding, be sure all Preflight Checks have passed!\n\nPlease refer to our Quick Start Guide:\n$lug_wiki\n\nAre you ready to continue?"
    else
        # No errors
        install_question="Before proceeding, please refer to our Quick Start Guide:\n$lug_wiki\n\nAll Preflight Checks have passed\nAre you ready to continue?"
    fi

    if message question "$install_question"; then
        # Detect which version of Lutris is installed
        if [ "$lutris_native" = "true" ] && [ "$lutris_flatpak" = "true" ]; then
            # Both versions of Lutris are installed so ask the user
            if message options "Flatpak" "Native" "This Helper has detected both the Native and Flatpak versions of Lutris\nWhich version would you like to use?"; then
                # Native version
                install_version="native"
            else
                # Flatpak version
                install_version="flatpak"
            fi
        elif [ "$lutris_native" = "true" ]; then
            # Native version only
            install_version="native"
        elif [ "$lutris_flatpak" = "true" ]; then
            # Flatpak version only
            install_version="flatpak"
        else
            # We shouldn't get here
            debug_print exit "Script error: Unable to detect Lutris version in install_game_lutris function. Aborting."
        fi

        # Create a temporary log file
        tmp_install_log="$(mktemp --suffix=".log" -t "lughelper-install-XXX")"

        # Run the appropriate installer
        if [ "$install_version" = "native" ]; then
            lutris --debug --install "$lutris_install_script" >"$tmp_install_log" 2>&1 &
        elif [ "$install_version" = "flatpak" ]; then
            flatpak run --file-forwarding net.lutris.Lutris --debug --install @@ "$lutris_install_script" @@ >"$tmp_install_log" 2>&1 &
        else
            # We shouldn't get here
            debug_print exit "Script error: Unknown condition for install_version in install_game_lutris() function. Aborting."
        fi

        message info "The installation will continue in Lutris. The debug log will be written to $tmp_install_log"
    fi
}

# Install the game without Lutris
install_game_wine() {
    # Double check that wine is installed
    if [ ! -x "$(command -v wine)" ]; then
        message error "Wine does not appear to be installed.\nPlease refer to our Quick Start Guide:\n$lug_wiki"
        return 1
    fi
    # Check if the install script exists
    if [ ! -f "$wine_launch_script" ]; then
        message error "Game launch script not found! Unable to proceed.\n\n$wine_launch_script\n\nIt is included in our official releases here:\n$releases_url"
        return 1
    fi

    # Call the preflight check and confirm the user is ready to proceed
    preflight_check "wine"
    if [ "$?" -eq 1 ]; then
        # There were errors
        install_question="Before proceeding, be sure all Preflight Checks have passed!\n\nPlease refer to our Quick Start Guide:\n$lug_wiki\n\nAre you ready to continue?"
    else
        # No errors
        install_question="Before proceeding, please refer to our Quick Start Guide:\n$lug_wiki\n\nAll Preflight Checks have passed\nAre you ready to continue?"
    fi
    if ! message question "$install_question"; then
        return 1
    fi

    # Get the install path from the user
    if message question "Would you like to use the default install path?\n\n$HOME/Games/star-citizen"; then
        # Set the default install path
        install_dir="$HOME/Games/star-citizen"
    else
        if [ "$use_zenity" -eq 1 ]; then
            if message options "Create my own prefix dir" "Continue" "After clicking Continue, select your Star Citizen install location.\nA new subdirectory named 'star-citizen' will be created in the selected location. This will be your wine prefix.\n\nIf you know what you are doing and want to create your own prefix directory, choose \"Create my own prefix dir\""; then
                # Default, create the star-citizen directory
                install_prefix="star-citizen"
            else
                # User will create their own prefix directory
                install_prefix=""
            fi

            # Get the install path from the user
            while true; do
                install_dir="$(zenity --file-selection --directory --title="Choose your Star Citizen install directory" --filename="$HOME/" 2>/dev/null)"

                if [ "$?" -eq -1 ]; then
                    message error "An unexpected error has occurred. The Helper is unable to proceed."
                    return 1
                elif [ -z "$install_dir" ]; then
                    # User clicked cancel or something else went wrong
                    message warning "Installation cancelled."
                    return 1
                fi

                # Add the wine prefix subdirectory to the install path
                if [ -n "$install_prefix" ]; then
                    install_dir="$install_dir/$install_prefix"
                fi

                # Sanity check the chosen directory a bit to catch some possible mistakes
                if [ "$install_dir" = "/" ] || [ "$install_dir" = "$HOME" ] || [ "$install_dir" = "$HOME/Games" ]; then
                    if message question "Something seems off! This directory will become your wine prefix. Are you really sure this is what you want?\n\n$install_dir"; then
                        break
                    fi
                else
                    # All good, break out of the loop and continue
                    break
                fi
            done
        else
            # No Zenity, use terminal-based menus
            clear
            # Get the install path from the user
            printf "Enter the desired Star Citizen install path (case sensitive)\nie. /home/USER/Games/star-citizen\n\n"
            while read -rp "Install path: " install_dir; do
                if [ -z "$install_dir" ]; then
                    printf "Invalid directory. Please try again.\n\n"
                elif [ ! -d "$install_dir" ]; then
                    if message question "That directory does not exist.\nWould you like it to be created for you?\n"; then
                        break
                    fi
                else
                    break
                fi
            done
        fi
    fi

    # Create the game path
    mkdir -p "$install_dir"

    # If we can't use the system wine, we'll need to have the user select a custom wine runner to use
    wine_path="$(command -v wine | xargs dirname)"
    if [ "$system_wine_ok" = "false" ]; then
        debug_print continue "Your system Wine does not meet the minimum requirements for Star Citizen!"
        debug_print continue "A custom wine runner will be automatically downloaded and used."

        download_dirs=("wine" "$install_dir/runners")

        # Install the default wine runner into the prefix
        download_wine
        # Make sure the wine download worked
        if [ "$?" -eq 1 ]; then
            message error "Something went wrong while installing ${default_runner}!\nGame installation cannot proceed."
            return 1
        fi

        wine_path="$install_dir/runners/$downloaded_item_name/bin"
    fi

    # Download winetricks
    download_winetricks
    # Abort if the winetricks download failed
    if [ "$?" -eq 1 ]; then
        message error "Unable to install Star Citizen without winetricks. Aborting."
        return 1
    fi

    # Download RSI installer to tmp
    download_file "$rsi_installer_url" "$rsi_installer" "installer"
    # Sanity check
    if [ ! -f "$tmp_dir/$rsi_installer" ]; then
        # Something went wrong with the download and the file doesn't exist
        message error "Something went wrong; the installer could not be downloaded!"
        return 1
    fi

    # Create a temporary log file
    tmp_install_log="$(mktemp --suffix=".log" -t "lughelper-install-XXX")"
    debug_print continue "Installation log file created at $tmp_install_log"

    # Create the new prefix and install powershell
    export WINE="$wine_path/wine"
    export WINESERVER="$wine_path/wineserver"
    export WINEPREFIX="$install_dir"
    debug_print continue "Preparing the wine prefix. Please wait; this will take a moment..."
    "$winetricks_bin" -q arial tahoma dxvk powershell win11 >"$tmp_install_log" 2>&1

    if [ "$?" -eq 1 ]; then
        if message question "Wine prefix creation failed. Aborting installation.\nThe install log was written to\n$tmp_install_log\n\nDo you want to delete\n${install_dir}?"; then
            debug_print continue "Deleting $install_dir..."
            rm -r --interactive=never "$install_dir"
        fi
        "$wine_path"/wineserver -k
        return 1
    fi

    # Add registry key that prevents wine from creating unnecessary file type associations
    "$wine_path"/wine reg add "HKEY_CURRENT_USER\Software\Wine\FileOpenAssociations" /v Enable /d N /f >>"$tmp_install_log" 2>&1

    # Run the installer
    debug_print continue "Installing the launcher. Please wait; this will take a moment..."
    "$wine_path"/wine "$tmp_dir/$rsi_installer" /S >>"$tmp_install_log" 2>&1

    if [ "$?" -eq 1 ]; then
        # User cancelled or there was an error
        if message question "Installation aborted. The install log was written to\n$tmp_install_log\n\nDo you want to delete\n${install_dir}?"; then
            debug_print continue "Deleting $install_dir..."
            rm -r --interactive=never "$install_dir"
        fi
        "$wine_path"/wineserver -k
        return 0
    fi

    # Kill the wine process after installation
    # To prevent unexpected lingering background wine processes, it should be launched by the user attached to a terminal
    "$wine_path"/wineserver -k

    # Save the install location to the Helper's config files
    reset_helper "switchprefix"
    wine_prefix="$install_dir"
    if [ -d "$wine_prefix/$default_install_path" ]; then
        game_path="$wine_prefix/$default_install_path/$sc_base_dir"
    fi
    getdirs

    # Verify that we have an installed game path
    if [ -z "$game_path" ]; then
        message error "Something went wrong during installation. Unable to locate the expected game path. Aborting."
        return 1
    fi

    # Copy game launch script to the wine prefix root directory
    debug_print continue "Copying game launch script to ${install_dir}..."
    if [ -f "$install_dir/$wine_launch_script_name" ]; then
        # Back it up if it already exists
        cp "$install_dir/$wine_launch_script_name" "$install_dir/$(basename "$wine_launch_script_name" .sh).bak"
    fi
    cp "$wine_launch_script" "$install_dir"
    installed_launch_script="$install_dir/$wine_launch_script_name"

    # Update WINEPREFIX in game launch script
    sed -i "s|^export WINEPREFIX=.*|export WINEPREFIX=\"$install_dir\"|" "$installed_launch_script"

    # Update Wine binary in game launch script
    post_download_sed_string="export wine_path="
    sed -i "s|^${post_download_sed_string}.*|${post_download_sed_string}\"${wine_path}\"|" "$installed_launch_script"

    # Modify the .desktop files installed by wine to exec the game launch script
    debug_print continue "Updating .desktop files installed by wine..."

    # Copy the bundled RSI Launcher icon to the .local icons directory
    if [ -f "$rsi_icon" ]; then
        mkdir -p "$HOME/.local/share/icons/hicolor/256x256/apps" && 
        cp "$rsi_icon" "$HOME/.local/share/icons/hicolor/256x256/apps"
    fi

    # Modify $HOME/Desktop/RSI Launcher.desktop
    home_desktop_file="${XDG_DESKTOP_DIR:-$HOME/Desktop}/RSI Launcher.desktop"
    if [ -f "$home_desktop_file" ]; then
        # Replace the exec line with our launch script
        sed -i "s|^Exec=env.*|Exec=$installed_launch_script|" "$home_desktop_file"
        # Quote exec line
        sed -i '/^Exec=/s/=/="/' "$home_desktop_file"
        sed -i '/^Exec=/s/$/"/' "$home_desktop_file"
        # Escape spaces in path line
        sed -i '/^Path=/s/ /\\\s/g' "$home_desktop_file"
        # Replace icon
        sed -i "s|^Icon=.*|Icon=$rsi_icon_name|" "$home_desktop_file"
        debug_print continue "Updated $home_desktop_file"
    else
        debug_print continue "Unable to find $home_desktop_file"
    fi

    # Modify $HOME/.local/share/applications/wine/Programs/Roberts Space Industries/RSI Launcher.desktop
    localshare_desktop_file="$data_dir/applications/wine/Programs/Roberts Space Industries/RSI Launcher.desktop"
    if [ -f "$localshare_desktop_file" ]; then
        # Replace the exec line with our launch script
        sed -i "s|^Exec=env.*|Exec=$installed_launch_script|" "$localshare_desktop_file"
        # Quote exec line
        sed -i '/^Exec=/s/=/="/' "$localshare_desktop_file"
        sed -i '/^Exec=/s/$/"/' "$localshare_desktop_file"
        # Escape spaces in path line
        sed -i '/^Path=/s/ /\\\s/g' "$localshare_desktop_file"
        # Replace icon
        sed -i "s|^Icon=.*|Icon=$rsi_icon_name|" "$localshare_desktop_file"
        debug_print continue "Updated $localshare_desktop_file"
    else
        debug_print continue "Unable to find $localshare_desktop_file"
    fi

    # Update the .desktop file database if the command is available
    if [ -x "$(command -v update-desktop-database)" ]; then
        debug_print continue "Running update-desktop-database..."
        update-desktop-database "$HOME/.local/share/applications"
    fi

    message info "Installation has finished. The install log was written to $tmp_install_log\n\nTo start the RSI Launcher, run the following launch script in a terminal\nEdit the environment variables in the script as needed:\n     $installed_launch_script\n\nYou may also start the RSI Launcher using the following .desktop files:\n     $home_desktop_file\n     $localshare_desktop_file"
}

# Download a default wine runner for use by the non-lutris installer
# Expects download_dirs to be set before calling
download_wine() {
    if [ "${#download_dirs[@]}" -eq 0 ]; then
        debug_print exit "Script error: The array 'download_dirs' was not set before calling the download_wine function. Aborting."
    fi

    # Set up variables needed for the download functions, quick and dirty
    # For more details, see their usage in the download_select_install and download_install functions
    declare -n download_sources=runner_sources
    download_type="runner"
    download_versions=("$default_runner")
    contributor_name="${download_sources[$default_runner_source]}"
    contributor_url="${download_sources[$default_runner_source+1]}"
    case "$contributor_url" in
        https://api.github.com/*)
            download_url_type="github"
            ;;
        https://gitlab.com/api/v4/projects/*)
            download_url_type="gitlab"
            ;;
        *)
            debug_print exit "Script error:  Unknown api/url format in ${download_type}_sources array. Aborting."
            ;;
    esac

    # Call the download_install function with the above options to install the default wine runner
    download_install 0

    if [ "$?" -eq 1 ]; then
        return 1
    fi
}

# Download winetricks to a temporary file
download_winetricks() {
    download_file "$winetricks_url" "winetricks" "winetricks"

    # Sanity check
    if [ ! -f "$tmp_dir/winetricks" ]; then
        # Something went wrong with the download and the file doesn't exist
        message error "Something went wrong; winetricks could not be downloaded!"
        return 1
    fi

    # Save the path to the downloaded binary
    winetricks_bin="$tmp_dir/winetricks"

    # Make it executable
    chmod +x "$winetricks_bin"
}

# Install powershell verb into the game's wine prefix
install_powershell() {
    # Download winetricks
    download_winetricks

    # Abort if the winetricks download failed
    if [ "$?" -eq 1 ]; then
        message error "Unable to install powershell without winetricks. Aborting."
        return 1
    fi

    # Update directories
    getdirs

    # Install powershell
    if [ "$?" -ne 1 ]; then
        debug_print continue "Installing PowerShell into ${wine_prefix}..."
        WINEPREFIX="$wine_prefix" "$winetricks_bin" -q powershell
        message info "PowerShell operation complete. See terminal output for details."
    fi
}

# Format some URLs for Zenity
format_urls() {
    if [ "$use_zenity" -eq 1 ]; then
        releases_url="<a href='$releases_url'>$releases_url</a>"
        lug_wiki="<a href='$lug_wiki'>$lug_wiki</a>"
        lug_wiki_nixos="<a href='$lug_wiki_nixos'>$lug_wiki_nixos</a>"
    fi
}

# Get the latest release version of a repo. Expects "user/repo_name" as input
# Credits for this go to https://gist.github.com/lukechilds/a83e1d7127b78fef38c2914c4ececc3c
get_latest_release() {
    # Sanity check
    if [ "$#" -lt 1 ]; then
        debug_print exit "Script error: The get_latest_release function expects one argument. Aborting."
    fi

    curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
        grep '"tag_name":' |                                            # Get tag line
        sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}

# Get a random Penguin's Star Citizen referral code
referral_randomizer() {
    # Populate the referral codes array
    referral_codes=("STAR-4TZD-6KMM" "STAR-4XM2-VM99" "STAR-2NPY-FCR2" "STAR-T9Z9-7W6P" "STAR-VLBF-W2QR" "STAR-BYR6-YHMF" "STAR-3X2H-VZMX" "STAR-BRWN-FB9T" "STAR-FG6Y-N4Q4" "STAR-VLD6-VZRG" "STAR-T9KF-LV77" "STAR-4XHB-R7RF" "STAR-9NVF-MRN7" "STAR-3Q4W-9TC3" "STAR-3SBK-7QTT" "STAR-XFBT-9TTK" "STAR-F3H9-YPHN" "STAR-BYK6-RCCL" "STAR-XCKH-W6T7" "STAR-H292-39WK" "STAR-ZRT5-PJB7" "STAR-GMBP-SH9Y" "STAR-PLWB-LMFY" "STAR-TNZN-H4ZT" "STAR-T5G5-L2GJ" "STAR-6TPV-7QH2" "STAR-THHD-TV3Y" "STAR-7ZFS-PK2L" "STAR-SRQN-43TB" "STAR-9TDG-D4H9" "STAR-BPH3-THJC" "STAR-HL3M-R5KC" "STAR-GBS5-LTVB" "STAR-CJ3Y-KZZ4" "STAR-5GRM-7HBY" "STAR-G2GX-Y2QJ" "STAR-YWY3-H4XX" "STAR-6VGM-PTKC" "STAR-T6MZ-QFHX" "STAR-T2K6-LXFW" "STAR-XN25-9CJJ" "STAR-47V3-4QGB" "STAR-YD4Z-TQZV" "STAR-XLN7-9XNJ" "STAR-N62T-2R39" "STAR-3S3D-9HXQ" "STAR-TRZF-NMCV" "STAR-TLLJ-SMG4" "STAR-MFT6-Q44H" "STAR-TZX2-TPWF" "STAR-WCHN-4ZMX" "STAR-2GHY-WB4F" "STAR-KLM2-R4SX" "STAR-RYXQ-PBZB" "STAR-BSTC-NQPW" "STAR-X32P-J2NS" "STAR-9DMZ-CXWW" "STAR-ZDC2-TDP9" "STAR-J3PJ-RH2K")
    # Pick a random array element. Scale a floating point number for
    # a more random distribution than simply calling RANDOM
    random_code="${referral_codes[$(awk '{srand($2); print int(rand()*$1)}' <<< "${#referral_codes[@]} $RANDOM")]}"

    message info "Your random Penguin's referral code is:\n\n$random_code\n\nThank you!"
}

quit() {
    exit 0
}


############################################################################
######## MAIN ##############################################################
############################################################################

# Zenity availability/version check
use_zenity=0
# Initialize some variables
menu_option_height="0"
menu_text_height_zenity4="0"
menu_height_max="0"
if [ -x "$(command -v zenity)" ]; then
    if zenity --version >/dev/null; then
        use_zenity=1
        zenity_version="$(zenity --version)"

        # Zenity 4.0.0 uses libadwaita, which changes fonts/sizing
        # Add pixels to each menu option depending on the version of zenity in use
        # used to dynamically determine the height of menus
        # menu_text_height_zenity4 = Add extra pixels to the menu title/description height for libadwaita bigness
        if [ "$zenity_version" != "4.0.0" ] && 
            [ "$zenity_version" = "$(printf "%s\n%s" "$zenity_version" "4.0.0" | sort -V | head -n1)" ]; then
            # zenity 3.x menu sizing
            menu_option_height="26"
            menu_text_height_zenity4="0"
            menu_height_max="400"
        else
            # zenity 4.x+ menu sizing
            menu_option_height="45"
            menu_text_height_zenity4="120"
            menu_height_max="800"
        fi
    else
        # Zenity is broken
        debug_print continue "Zenity failed to start. Falling back to terminal menus"
    fi
fi

# Check if this is the user's first run of the Helper
if [ -f "$conf_dir/$conf_subdir/$firstrun_conf" ]; then
    is_firstrun="$(cat "$conf_dir/$conf_subdir/$firstrun_conf")"
fi
if [ "$is_firstrun" != "false" ]; then
    is_firstrun="true"
fi

# Set defaults
game_version="$live_dir"

# Format some URLs for Zenity if the Helper was not invoked with command-line arguments (handle those separately below)
if [ "$#" -eq 0 ]; then
    format_urls
fi

# Check if a newer verison of the script is available
latest_version="$(get_latest_release "$repo")"

# Sort the versions and check if the installed Helper is smaller
if [ "$latest_version" != "$current_version" ] &&
   [ "$current_version" = "$(printf "%s\n%s" "$current_version" "$latest_version" | sort -V | head -n1)" ]; then

    message info "The latest version of the LUG Helper is $latest_version\nYou are using $current_version\n\nYou can download new releases here:\n$releases_url"
fi

# If invoked with command line arguments, process them and exit
if [ "$#" -gt 0 ]; then
    while [ "$#" -gt 0 ]
    do
        # Victor_Tramp expects the spanish inquisition.
        case "$1" in
            --help | -h )
                printf "Star Citizen Linux Users Group Helper Script
Usage: lug-helper <options>
  -p, --preflight-check         Run system optimization checks
  -i, --install [lutris|wine]   Install Star Citizen (default: lutris)
  -m, --manage-wine-runners     Install or remove Wine runners
  -l, --manage-lutris-runners   Install or remove Lutris runners
  -k, --manage-lutris-dxvk      Install or remove Lutris DXVK versions
  -e, --eac                     Delete Easy Anti-Cheat Workaround
  -u, --delete-user-folder      Delete Star Citizen USER dir, preserve keybinds
  -s, --delete-shaders          Delete Star Citizen shaders
  -c, --delete-dxvk-cache       Delete Star Citizen dxvk cache file
  -t, --target [live|ptu|eptu]  Target LIVE/PTU/EPTU (default: live)
  -g, --no-gui                  Use terminal menus instead of a Zenity GUI
  -r, --get-referral            Get a random LUG member's referral code
  -d, --show-directories        Show all Star Citizen and Helper directories
  -w, --show-wiki               Show the LUG Wiki
  -x, --reset-helper            Delete saved lug-helper configs
  -v, --version                 Display version info and exit
"
                exit 0
                ;;
            --preflight-check | -p )
                cargs+=("preflight_check")
                ;;
            --install | -i )
                install_method="$2"
                if [ "$install_method" = "lutris" ] || [ "$install_method" = "LUTRIS" ] || [ "$install_method" = "" ]; then
                    cargs+=("install_game_lutris")
                elif [ "$install_method" = "wine" ] || [ "$install_method" = "WINE" ]; then
                    cargs+=("install_game_wine")
                else
                    printf "$0: Invalid argument '%s'\n" "$install_method"
                    exit 0
                fi
                # Shift forward one argument
                shift
                ;;
            --manage-wine-runners | -m )
                cargs+=("runner_manage_wine")
                ;;
            --manage-lutris-runners | -l )
                cargs+=("runner_manage_lutris")
                ;;
            --manage-lutris-dxvk | -k )
                cargs+=("dxvk_manage_lutris")
                ;;
            --eac | -e )
                cargs+=("rm_eac_workaround")
                ;;
            --delete-user-folder | -u )
                cargs+=("rm_userdir")
                ;;
            --delete-shaders | -s )
                cargs+=("rm_shaders")
                ;;
            --delete-dxvk-cache | -c )
                cargs+=("rm_dxvkcache")
                ;;
            --target | -t )
                game_version="$2"
                if [ "$game_version" = "live" ] || [ "$game_version" = "LIVE" ]; then
                    game_version="$live_dir"
                elif [ "$game_version" = "ptu" ] || [ "$game_version" = "PTU" ]; then
                    game_version="$ptu_dir"
                elif [ "$game_version" = "eptu" ] || [ "$game_version" = "EPTU" ]; then
                    game_version="$eptu_dir"
                else
                    printf "$0: Invalid argument '%s'\n" "$game_version"
                    exit 0
                fi
                # Shift forward one argument
                shift
                ;;
            --no-gui | -g )
                # If zenity is unavailable, it has already been set to 0
                # and this setting has no effect
                use_zenity=0
                ;;
            --get-referral | -r )
                cargs+=("referral_randomizer")
                ;;
            --show-directories | -d )
                cargs+=("display_dirs")
                ;;
            --show-wiki | -w )
                cargs+=("display_wiki")
                ;;
            --reset-helper | -x )
                cargs+=("reset_helper")
                ;;
            --version | -v )
                printf "LUG Helper %s\n" "$current_version"
                exit 0
                ;;
            * )
                printf "$0: Invalid option '%s'\n" "$1"
                exit 0
                ;;
        esac
        # Shift forward to the next argument and loop again
        shift
    done

    # Format some URLs for Zenity
    format_urls

    # Call the requested functions and exit
    if [ "${#cargs[@]}" -gt 0 ]; then
        cmd_line="true"
        for (( x=0; x<"${#cargs[@]}"; x++ )); do
            ${cargs[x]}
        done
        exit 0
    fi
fi

# Detect if NixOS is being used and direct user to wiki
if [ "$is_nixos" -eq 1 ]; then
    message info "It looks like you're using NixOS\nPlease see our wiki for NixOS-specific configuration requirements:\n\n$lug_wiki_nixos"
fi

# Set up the main menu heading
menu_heading_zenity="<b><big>Greetings, Space Penguin!</big>\n\nThis tool is provided by the Star Citizen Linux Users Group</b>\nFor help, see our wiki: $lug_wiki"
menu_heading_terminal="Greetings, Space Penguin!\n\nThis tool is provided by the Star Citizen Linux Users Group\nFor help, see our wiki: $lug_wiki"

# First run
firstrun_message="It looks like this is your first time running the Helper\n\nWould you like to run the Preflight Check and install Star Citizen?"
if [ "$use_zenity" -eq 1 ]; then
    firstrun_message="$menu_heading_zenity\n\n$firstrun_message"
else
    firstrun_message="$menu_heading_terminal\n\n$firstrun_message"
fi
if [ "$is_firstrun" = "true" ]; then
    if message question "$firstrun_message"; then
        if message options "Wine" "Lutris" "Which install method would you like to use?"; then
            install_game_lutris
        else
            install_game_wine
        fi
    fi
    # Store the first run state for subsequent launches
    if [ ! -d "$conf_dir/$conf_subdir" ]; then
        mkdir -p "$conf_dir/$conf_subdir"
    fi
    echo "false" > "$conf_dir/$conf_subdir/$firstrun_conf"
fi

# Loop the main menu until the user selects quit
while true; do
    # Configure the menu
    menu_text_zenity="$menu_heading_zenity"
    menu_text_terminal="$menu_heading_terminal"
    menu_text_height="120"
    menu_type="radiolist"

    # Configure the menu options
    preflight_msg="Preflight Check (System Optimization)"
    install_msg_wine="Install Star Citizen with Wine"
    install_msg_lutris="Install Star Citizen with Lutris"
    runners_msg_wine="Manage Wine Runners (non-Lutris)"
    runners_msg_lutris="Manage Lutris Runners"
    dxvk_msg="Manage Lutris DXVK Versions"
    maintenance_msg="Maintenance and Troubleshooting"
    randomizer_msg="Get a random Penguin's Star Citizen referral code"
    quit_msg="Quit"

    # Set the options to be displayed in the menu
    menu_options=("$preflight_msg" "$install_msg_wine" "$install_msg_lutris" "$runners_msg_wine" "$runners_msg_lutris" "$dxvk_msg" "$maintenance_msg" "$randomizer_msg" "$quit_msg")
    # Set the corresponding functions to be called for each of the options
    menu_actions=("preflight_check" "install_game_wine" "install_game_lutris" "runner_manage_wine" "runner_manage_lutris" "dxvk_manage_lutris" "maintenance_menu" "referral_randomizer" "quit")

    # Calculate the total height the menu should be
    # menu_option_height = pixels per menu option
    # #menu_options[@] = number of menu options
    # menu_text_height = height of the title/description text
    # menu_text_height_zenity4 = added title/description height for libadwaita bigness
    menu_height="$(($menu_option_height * ${#menu_options[@]} + $menu_text_height + $menu_text_height_zenity4))"

    # Set the label for the cancel button
    cancel_label="Quit"

    # Call the menu function.  It will use the options as configured above
    menu
done
