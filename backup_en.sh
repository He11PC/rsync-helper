#!/bin/bash

###############################################################
# FILE          : backup.sh
# DESCRIPTION   : Facilitate your regular rsync backups
# AUTHOR        : HellPC
# DATE          : 2026.02.11
# README        : https://github.com/He11PC/rsync-helper#readme
# LICENSE       : GPLv3
###############################################################


# --------------
# Initialisation
# --------------

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG_FILE="$SCRIPT_DIR/config.cfg"
LOG_DIR="$SCRIPT_DIR/log"

RSYNC_RESULT=()
WG_DISCONENCT=()

function init() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ '$CONFIG_FILE' configuration file not found" >&2
        text_exit
        exit 1
    fi
    source "$CONFIG_FILE"

    for i in "${!BACKUP_TARGET[@]}"; do
        RSYNC_RESULT+=("")
    done
}



# ---------
# Interface
# ---------

function text_introduction() {
    echo "Which backup do you want to perform?"
    echo
}

function text_backup_canceled() {
    echo
    echo "Backup canceled"
    draw_line
}

function text_exit() {
    echo
    read -p "Press [Entrer] to exit"
}

# ----

# $1 = max choice number
function error_choice() {
    echo
    echo "⚠️ Please enter a number between 1 and $1"
    echo
}

function error_path() {
    draw_line
    echo
    echo "⚠️ A path seems inaccessible"
    echo
    echo "Perhaps a USB storage device is unplugged?"
    draw_line
}

function error_rsync_args() {
    draw_line
    echo
    echo "⚠️ Unable to retrieve rsync arguments"
    echo
    echo "Please check your configuration file"
    draw_line
}

# ----

function draw_line() {
    echo
    printf '%.s─' $(seq 1 $(tput cols))
    echo
}

# ----

function ask_confirmation() {
    read -p "$1 ([y]es / [N]o): "
    case $(echo $REPLY | tr '[A-Z]' '[a-z]') in
        y|yes)  echo "yes" ;;
        *)      echo "no" ;;
    esac
}

function ask_backup_target() {
    while true; do

        text_introduction

        for i in "${!BACKUP_TARGET[@]}"; do
            local option="$((i+1))) ${BACKUP_TARGET[$i]}"

            # Last backup date
            local log_file="$LOG_DIR/id$((i+1)).log"
            if [[ -f "$log_file" ]]; then
                local timestamp=$(stat -c "%Y" "$log_file")
                local date=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S")
                option+="\t$date"
            fi

            # Current session backup result
            local last_result="${RSYNC_RESULT[$i]}"
            case $last_result in
                "") ;;
                "0") option+="\t✅" ;;
                *) option+="\t❌ code $last_result" ;;
            esac

            echo -e "$option"
        done | column -s $'\t' -t

        local options_count=$(("${#BACKUP_TARGET[@]}"+1))
        echo "$options_count) Exit"

        echo
        read -rp ": " user_choice

        if [[ "$user_choice" =~ ^[0-9]+$ ]] && (( user_choice >= 1 && user_choice < options_count )); then
            local index="$((user_choice - 1))"
            backup_initiate "$index"
        elif [[ "$user_choice" == "$options_count" ]] || [[ "$user_choice" == "q" ]]; then
            break
        else
            error_choice "$options_count"
        fi
    done
}


# ---------
# WireGuard
# ---------

# $1 = backup index (Int)
function wg_connect() {
    local wg_connexion="${BACKUP_WG_REQUIRED[$1]}"

    if [[ -n "$wg_connexion" ]] && ! nmcli -t connection show "$wg_connexion" | grep -q "^GENERAL.STATE:activated$"; then
        draw_line
        echo
        echo "Connecting to VPN $wg_connexion ..."

        if nmcli connection up "$wg_connexion"; then
            echo "✅ Connection success"

            local found=0
            for item in "${WG_DISCONNECT[@]}"; do
                if [[ "$item" == "$wg_connexion" ]]; then
                    found=1
                    break
                fi
            done

            if [ "$found" -eq 0 ]; then
                WG_DISCONNECT+=("$wg_connexion")
            fi

            return 0
        else
            echo "❌ Connection failed"
            return 1
        fi
    fi
}

function wg_disconnect() {
    local wait="false"

    draw_line

    for wg_connexion in "${WG_DISCONNECT[@]}"; do
        echo
        echo "Disconnecting from VPN $wg_connexion ..."

        if nmcli connection down "$wg_connexion"; then
            echo "✅ Disconnection success"
        else
            echo "⚠️ Disconnection failed"
        fi

        wait="true"
    done

    WG_DISCONNECT=()

    if [[ "$wait" == "true" ]]; then
        sleep 3
    fi

    return 0
}


# ---------------
# rsync arguments
# ---------------

# $1 = is source (true/false)
# $2 = backup index (Int)
function get_path() {
    local is_source="$1"
    local index="$2"

    local uuid=""
    local path=""

    # Is source ?
    if [[ "$is_source" == "true" ]]; then
        uuid="${BACKUP_SOURCE_UUID[$index]}"
        path="${BACKUP_SOURCE[$index]}"
    else
        uuid="${BACKUP_DESTINATION_UUID[$index]}"
        path="${BACKUP_DESTINATION[$index]}"
    fi

    # Has UUID ?
    if [[ -z "$uuid" ]]; then
        echo "$path"
    else
        local usb_mount=$( findmnt -noTARGET "/dev/disk/by-uuid/$uuid" )
        if [[ -z "$usb_mount" ]]; then
            echo ""
        else
            echo "${usb_mount}${path}"
        fi
    fi
}

# $1 = is simulation (true/false)
# $2 = backup index (Int)
# $3 = variable to fill (nameref)
function get_rsync_args() {
    local is_simulation="$1"
    local index="$2"
    local -n rsync_args_ref="$3"

    rsync_args_ref=()
    if [[ "$is_simulation" == "true" ]]; then
        rsync_args_ref+=( --dry-run )
    fi

    local -n stored_rsync_args_ref="${BACKUP_RSYNC_ARGS[$index]}"
    rsync_args_ref+=( "${stored_rsync_args_ref[@]}" )
}


# ------
# Backup
# ------

# $1 = backup index (Int)
function backup_initiate() {
    local index="$1"
    local error="false"

    local target="${BACKUP_TARGET[$index]}"
    local source=$(get_path "true" "$index")
    local destination=$(get_path "false" "$index")

    clear
    echo "Backup $target :"
    echo

    # Source
    if [[ -z "$source" ]]; then
        echo "Source      => ERROR"
        error="true"
    else
        echo "Source      => $source"
    fi

    # Destination
    if [[ -z "$destination" ]]; then
        echo "Destination => ERROR"
        error="true"
    else
        echo "Destination => $destination"
    fi

    # Verification
    if [[ "$error" == "true" ]]; then
        error_path
    elif wg_connect "$index"; then
        # Backup
        draw_line
        echo
        if [[ "yes" == $(ask_confirmation "Perform a preliminary simulation?") ]]; then
            backup_process "true" "$index"
            echo
            if [[ "yes" == $(ask_confirmation "Perform the backup?") ]]; then
                backup_process "false" "$index"
            else
                text_backup_canceled
            fi
        else
            backup_process "false" "$index"
        fi
    fi

    text_exit
    clear
}

# $1 = is simulation (true/false)
# $2 = backup index (Int)
function backup_process() {
    local is_simulation="$1"
    local index="$2"

    local source=$(get_path "true" "$index")
    local destination=$(get_path "false" "$index")

    # Verification
    if [[ -z "$source" ]] || [[ -z "$destination" ]]; then
         error_path
    else
        # Backup
        local rsync_args=()
        get_rsync_args "$is_simulation" "$index" "rsync_args"

        if [[ ${#rsync_args[@]} -eq 0 ]]; then
            error_rsync_args
        else
            echo
            if [[ "$is_simulation" == "true" ]]; then
                echo "Backup simulation:"
                echo
                echo "rsync ${rsync_args[@]} $source $destination"
                echo
                #rsync "${rsync_args[@]}" "$source" "$destination"
            else
                echo "Files backup:"
                echo

                local log_file="$LOG_DIR/id$((index+1)).log"
                mkdir -p "$(dirname "$log_file")"

                set -o pipefail
                {
                    echo "rsync ${rsync_args[@]} $source $destination"
                    echo
                    #rsync "${rsync_args[@]}" "$source" "$destination"
                } 2>&1 | tee "$log_file"
                RSYNC_RESULT["$index"]="$?"
                set +o pipefail
            fi
            draw_line
        fi
    fi
}


# ------
# Script
# ------

init
ask_backup_target
trap wg_disconnect EXIT INT TERM
exit 0
