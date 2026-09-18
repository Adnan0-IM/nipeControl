#!/bin/bash

# nipe-widget.sh - Robust helper script for DankMaterialShell Nipe Control Plugin
set -euo pipefail

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/nipeControl/config"
NIPE_DIR_SET="${NIPE_DIR:-}"

if [[ -z "$NIPE_DIR_SET" && -f "$CONFIG_FILE" ]]; then
    NIPE_DIR_SET=$(grep -E '^NIPE_DIR=' "$CONFIG_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
fi

DEFAULT_IP_API="https://ipinfo.io"

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

    local perl_bin
    perl_bin=$(command -v perl || echo "/usr/bin/perl")
    local output
    # First attempt non-interactive sudo using the absolute script path matching sudoers
    if output=$(cd "$NIPE_DIR" && sudo -n "$perl_bin" "nipe.pl" "$action" 2>&1); then
        echo "$output"
        return 0
    elif [[ "$output" =~ "password is required" || "$output" =~ "a password is required" ]] && [[ "$action" == "status" ]]; then
        echo "[!] ERROR: Sudo password required. Configure sudoers rule."
        return 0
    elif [[ "$action" == "status" ]]; then
        if [[ "$output" =~ "Status:" ]]; then
            echo "$output"
            return 0
        fi
        echo "[!] ERROR: Sudo password required. Configure sudoers rule."
        return 0
    elif command -v pkexec &>/dev/null; then
        pkexec "$perl_bin" "$NIPE_DIR/nipe.pl" "$action" 2>&1 || true
    else
        sudo "$perl_bin" "$NIPE_DIR/nipe.pl" "$action" 2>&1 || true
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

    local sys_missing=()
    command -v curl &>/dev/null || sys_missing+=("curl")
    command -v jq &>/dev/null || sys_missing+=("jq")
    command -v notify-send &>/dev/null || sys_missing+=("notify-send")

    # Clipboard check
    if ! command -v wl-copy &>/dev/null && ! command -v xclip &>/dev/null && ! command -v dms &>/dev/null; then
        sys_missing+=("clipboard-tool")
    fi

    if [[ ${#missing[@]} -eq 0 && ${#sys_missing[@]} -eq 0 ]]; then
        echo "OK"
    else
        local all_missing=("${missing[@]}" "${sys_missing[@]}")
        echo "MISSING:${all_missing[*]}"
    fi
}

# fetch_ip_info <ip> <api_base> -> prints pipe-separated fields: code|name|city|region|org
fetch_ip_info() {
    local ip="$1"
    local base="${2:-$DEFAULT_IP_API}"
    base="${base%/}"

    local json
    if [[ -n "$ip" && "$ip" != "Unknown" && "$ip" != "N/A" ]]; then
        json=$(curl -s --max-time 5 "${base}/${ip}/json" 2>/dev/null || echo "{}")
    else
        json=$(curl -s --max-time 5 "${base}/json" 2>/dev/null || echo "{}")
    fi

    # Ensure json is not empty and is valid JSON
    if [[ -z "$json" || "$json" == "{}" ]]; then
        echo "||||"
        return 0
    fi

    local code name city region org
    code=$(echo "$json" | jq -r '.country // empty' 2>/dev/null || true)
    name=$(echo "$json" | jq -r '.country_name // .name // empty' 2>/dev/null || true)
    city=$(echo "$json" | jq -r '.city // empty' 2>/dev/null || true)
    region=$(echo "$json" | jq -r '.region // empty' 2>/dev/null || true)
    org=$(echo "$json" | jq -r '.org // empty' 2>/dev/null || true)

    echo "${code}|${name}|${city}|${region}|${org}"
}

get_json_status() {
    local api="${1:-$DEFAULT_IP_API}"
    local deps_status
    deps_status=$(check_dependencies || echo "ERROR")
    if [[ "$deps_status" != "OK" ]]; then
        local missing_list=${deps_status#MISSING:}
        echo "{\"active\": false, \"ip\": \"N/A\", \"error\": \"Missing dependencies: $missing_list\", \"nipe_dir\": \"${NIPE_DIR:-not_found}\", \"country\": \"\", \"country_code\": \"\", \"city\": \"\", \"region\": \"\", \"org\": \"\"}"
        return 0
    fi

    if [[ -z "$NIPE_DIR" || ! -f "$NIPE_DIR/nipe.pl" ]]; then
        echo "{\"active\": false, \"ip\": \"N/A\", \"error\": \"Nipe directory not found. Install Nipe or set NIPE_DIR.\", \"nipe_dir\": \"\", \"country\": \"\", \"country_code\": \"\", \"city\": \"\", \"region\": \"\", \"org\": \"\"}"
        return 0
    fi

    local raw_output
    raw_output=$(run_nipe_cmd status)

    local active="false"
    local ip="Unknown"
    local error="null"
    local country_code=""
    local country=""
    local city=""
    local region=""
    local org=""

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

    if [[ "$active" == "true" ]]; then
        local info
        info=$(fetch_ip_info "$ip" "$api")
        IFS='|' read -r country_code country city region org <<< "$info"
    fi

    echo "{\"active\": $active, \"ip\": \"$ip\", \"error\": $error, \"nipe_dir\": \"$NIPE_DIR\", \"country\": \"$country\", \"country_code\": \"$country_code\", \"city\": \"$city\", \"region\": \"$region\", \"org\": \"$org\"}"
}

leak_test() {
    local api="${1:-$DEFAULT_IP_API}"
    local deps_status
    deps_status=$(check_dependencies || echo "ERROR")
    if [[ "$deps_status" != "OK" ]]; then
        local missing_list=${deps_status#MISSING:}
        echo "{\"ip_result\": \"unknown\", \"dns_result\": \"unknown\", \"ip_leak\": false, \"dns_leak\": false, \"exit_ip\": \"\", \"exit_country_code\": \"\", \"exit_country\": \"\", \"error\": \"Missing dependencies: $missing_list\"}"
        return 0
    fi

    if [[ -z "$NIPE_DIR" || ! -f "$NIPE_DIR/nipe.pl" ]]; then
        echo "{\"ip_result\": \"unknown\", \"dns_result\": \"unknown\", \"ip_leak\": false, \"dns_leak\": false, \"exit_ip\": \"\", \"exit_country_code\": \"\", \"exit_country\": \"\", \"error\": \"Nipe directory not found.\"}"
        return 0
    fi

    local raw_output
    raw_output=$(run_nipe_cmd status)

    local active="false"
    local ip="Unknown"

    if echo "$raw_output" | grep -qi "Status: true"; then
        active="true"
    fi

    local parsed_ip
    parsed_ip=$( (echo "$raw_output" | grep -i "Ip:" | awk '{print $NF}' | tr -d '\r\n') || true)
    if [[ -n "$parsed_ip" ]]; then
        ip="$parsed_ip"
    fi

    if [[ "$active" != "true" || "$ip" == "Unknown" || "$ip" == "N/A" ]]; then
        echo "{\"ip_result\": \"unknown\", \"dns_result\": \"unknown\", \"ip_leak\": false, \"dns_leak\": false, \"exit_ip\": \"\", \"exit_country_code\": \"\", \"exit_country\": \"\", \"error\": \"Nipe is not active. Start Nipe first.\"}"
        return 0
    fi

    local base
    base=$(printf '%s' "$api" | sed 's#/$##')
    local socs_port="${TOR_SOCKS_PORT:-9050}"
    local ip_result="unknown"
    local exit_ip=""
    local error=""

    exit_ip=$(curl -s --max-time 12 --socks5-hostname "127.0.0.1:${socs_port}" "${base}/ip" 2>/dev/null | tr -d '\r\n' || echo "")
    if [[ -n "$exit_ip" ]]; then
        if [[ "$exit_ip" == "$ip" ]]; then
            ip_result="pass"
        else
            ip_result="fail"
        fi
    else
        error="Tor SOCKS proxy (127.0.0.1:${socs_port}) unreachable for verification."
    fi

    local exit_country_code=""
    local exit_country=""
    local info
    info=$(fetch_ip_info "$exit_ip" "$api")
    IFS='|' read -r exit_country_code exit_country _city _region _org <<< "$info"

    local ip_leak="false"
    [[ "$ip_result" == "fail" ]] && ip_leak="true"

    echo "{\"ip_result\": \"$ip_result\", \"dns_result\": \"unknown\", \"ip_leak\": $ip_leak, \"dns_leak\": false, \"exit_ip\": \"$exit_ip\", \"exit_country_code\": \"$exit_country_code\", \"exit_country\": \"$exit_country\", \"error\": \"$error\"}"
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
    get_json_status "${2:-$DEFAULT_IP_API}"
    ;;
  check-deps)
    check_dependencies
    ;;
  path)
    echo "${NIPE_DIR:-not_found}"
    ;;
  leak-test)
    # Leak test removed per user request
    echo '{"ip_result":"unknown","dns_result":"unknown","ip_leak":false,"dns_leak":false,"exit_ip":"","exit_country_code":"","exit_country":"","error":"Leak test disabled."}'
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|json-status|check-deps|path|leak-test}"
    exit 1
    ;;
esac