#!/bin/bash

# nipe-widget.sh - Robust helper script for DankMaterialShell Nipe Control Plugin
set -euo pipefail

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/nipeControl/config"
NIPE_DIR_SET="${NIPE_DIR:-}"

if [[ -z "$NIPE_DIR_SET" && -f "$CONFIG_FILE" ]]; then
    NIPE_DIR_SET=$(grep -E '^NIPE_DIR=' "$CONFIG_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
fi

find_nipe_dir() {
    if [[ -n "$NIPE_DIR_SET" && -d "$NIPE_DIR_SET" && -f "$NIPE_DIR_SET/nipe.pl" ]]; then
        echo "$NIPE_DIR_SET"
        return 0
    fi

    local search_paths=(
        "$HOME/nipe"
        "$HOME/.local/share/nipe"
        "/opt/nipe"
        "/etc/nipe"
        "/usr/local/nipe"
    )

    for path in "${search_paths[@]}"; do
        if [[ -d "$path" && -f "$path/nipe.pl" ]]; then
            echo "$path"
            return 0
        fi
    done

    return 1
}

NIPE_DIR=$(find_nipe_dir || true)

run_nipe_cmd() {
    local action="$1"

    if [[ -z "$NIPE_DIR" || ! -f "$NIPE_DIR/nipe.pl" ]]; then
        echo "[!] ERROR: Nipe directory not found."
        return 1
    fi

    cd "$NIPE_DIR"

    if sudo -n true 2>/dev/null; then
        sudo -n perl nipe.pl "$action" 2>&1 || true
    elif [[ "$action" == "status" ]]; then
        # Status checks must not block waiting for password input
        echo "[!] ERROR: Sudo password required. Configure sudoers rule."
        return 0
    elif command -v pkexec &>/dev/null; then
        pkexec perl nipe.pl "$action" 2>&1 || true
    else
        sudo perl nipe.pl "$action" 2>&1 || true
    fi
}

check_dependencies() {
    local missing=()
    command -v perl &>/dev/null || missing+=("perl")
    perl -MConfig::Simple -e 1 2>/dev/null || missing+=("perl-config-simple")
    perl -MJSON -e 1 2>/dev/null || missing+=("perl-json")
    perl -MReadonly -e 1 2>/dev/null || missing+=("perl-readonly")
    perl -MIO::Socket::SSL -e 1 2>/dev/null || missing+=("perl-io-socket-ssl")
    perl -MNet::SSLeay -e 1 2>/dev/null || missing+=("perl-net-ssleay")

    if [[ ${#missing[@]} -eq 0 ]]; then
        echo "OK"
    else
        echo "MISSING:${missing[*]}"
    fi
}

get_json_status() {
    local deps_status
    deps_status=$(check_dependencies || echo "ERROR")
    if [[ "$deps_status" != "OK" ]]; then
        local missing_list=${deps_status#MISSING:}
        echo "{\"active\": false, \"ip\": \"N/A\", \"error\": \"Missing dependencies: $missing_list\", \"nipe_dir\": \"${NIPE_DIR:-not_found}\"}"
        return 0
    fi

    if [[ -z "$NIPE_DIR" || ! -f "$NIPE_DIR/nipe.pl" ]]; then
        echo "{\"active\": false, \"ip\": \"N/A\", \"error\": \"Nipe directory not found. Install Nipe or set NIPE_DIR.\", \"nipe_dir\": \"\"}"
        return 0
    fi

    local raw_output
    raw_output=$(run_nipe_cmd status)

    local active="false"
    local ip="Unknown"
    local error="null"

    if echo "$raw_output" | grep -qi "Status: true"; then
        active="true"
    elif echo "$raw_output" | grep -qi "Status: false"; then
        active="false"
    elif echo "$raw_output" | grep -qi "Sudo password required"; then
        error="\"Sudo password required. Configure sudoers rule (see README).\""
    elif echo "$raw_output" | grep -qi "must be run as root"; then
        error="\"Root permissions required.\""
    else
        local clean_err
        clean_err=$(echo "$raw_output" | tr -d '"\r\n' | head -c 120)
        if [[ -n "$clean_err" ]]; then
            error="\"$clean_err\""
        fi
    fi

    local parsed_ip
    parsed_ip=$( (echo "$raw_output" | grep -i "Ip:" | awk '{print $NF}' | tr -d '\r\n') || true)
    if [[ -n "$parsed_ip" ]]; then
        ip="$parsed_ip"
    fi

    echo "{\"active\": $active, \"ip\": \"$ip\", \"error\": $error, \"nipe_dir\": \"$NIPE_DIR\"}"
}

case "${1:-status}" in
  start|stop|restart)
    run_nipe_cmd "$1"
    ;;
  status)
    if [[ -z "$NIPE_DIR" || ! -f "$NIPE_DIR/nipe.pl" ]]; then
        echo "[!] ERROR: Nipe directory not found."
        exit 1
    fi
    run_nipe_cmd status
    ;;
  json-status)
    get_json_status
    ;;
  check-deps)
    check_dependencies
    ;;
  path)
    echo "${NIPE_DIR:-not_found}"
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|json-status|check-deps|path}"
    exit 1
    ;;
esac
