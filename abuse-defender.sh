#!/bin/bash

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Non-interactive flag ───────────────────────────────────────────────────────
NON_INTERACTIVE=false
for arg in "$@"; do
    case "$arg" in
        --non-interactive|-y|--auto|--defaults) NON_INTERACTIVE=true ;;
    esac
done

# ── Root check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    clear
    echo -e "${RED}${BOLD}Permission denied.${RESET}"
    echo -e "Run as root:  ${CYAN}sudo -i${RESET}"
    exit 1
fi

# ── Paths & constants ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
IP_LIST_FILE="$SCRIPT_DIR/abuse-ips.ipv4"

MALICIOUS_DOMAINS=(
    "appclick.co"
    "pushnotificationws.com"
)

# ── Load IP list ──────────────────────────────────────────────────────────────
if [[ -f "$IP_LIST_FILE" ]]; then
    IP_LIST=$(grep -v '^\s*#' "$IP_LIST_FILE" | grep -v '^\s*$')
else
    echo -e "${RED}Warning: abuse-ips.ipv4 not found at $IP_LIST_FILE${RESET}"
    IP_LIST=""
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
ask() {
    # ask <prompt> <default>  →  echoes "y" or "n"
    local prompt="$1" default="${2:-y}"
    if $NON_INTERACTIVE; then echo "$default"; return; fi
    local reply
    read -rp "$prompt" reply
    echo "${reply:-$default}"
}

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║       A B U S E   D E F E N D E R        ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${RESET}"
}

print_status() { echo -e "  ${GREEN}✔${RESET}  $1"; }
print_error()  { echo -e "  ${RED}✖${RESET}  $1"; }
print_warn()   { echo -e "  ${YELLOW}!${RESET}  $1"; }

_press_enter() {
    if ! $NON_INTERACTIVE; then
        echo ""
        read -rp "  Press Enter to continue…" _
    fi
}

# ── iptables helpers ──────────────────────────────────────────────────────────
ensure_iptables() {
    if ! command -v iptables &>/dev/null; then
        apt update -q && apt install -y iptables
    fi
    if ! dpkg -s iptables-persistent &>/dev/null; then
        # Pre-answer debconf questions so install is non-interactive
        echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
        echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
        DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent
    fi
}

ensure_chains() {
    local chain
    for chain in abuse-defender abuse-defender-custom abuse-defender-whitelist; do
        iptables -L "$chain" -n &>/dev/null || iptables -N "$chain"
        iptables -C INPUT  -j "$chain" 2>/dev/null || iptables -I INPUT  -j "$chain"
        iptables -C OUTPUT -j "$chain" 2>/dev/null || iptables -I OUTPUT -j "$chain"
    done
}

save_rules() {
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
}

# ── Menu ──────────────────────────────────────────────────────────────────────
main_menu() {
    while true; do
        clear
        print_header

        echo -e "  ${BOLD}Choose an option:${RESET}"
        echo ""
        echo -e "  ${GREEN}${BOLD}[1]${RESET}  Block Abuse IP-Ranges"
        echo -e "  ${CYAN}${BOLD}[2]${RESET}  Whitelist an IP / IP-Range"
        echo -e "  ${RED}${BOLD}[3]${RESET}  Block an IP / IP-Range manually"
        echo -e "  ${BLUE}${BOLD}[4]${RESET}  View Rules"
        echo -e "  ${YELLOW}${BOLD}[5]${RESET}  Clear all rules"
        echo -e "  ${MAGENTA}${BOLD}[6]${RESET}  Setup DNS  ${DIM}(Cloudflare 1.1.1.2 / Quad9 9.9.9.9)${RESET}"
        echo -e "  ${DIM}[7]  Exit${RESET}"
        echo ""
        echo -ne "  ${BOLD}→ ${RESET}"
        read -r choice
        echo ""

        case $choice in
            1) block_ips ;;
            2) whitelist_ips ;;
            3) block_custom_ips ;;
            4) view_rules ;;
            5) clear_chain ;;
            6) setup_dns ;;
            7) echo -e "  ${DIM}Goodbye.${RESET}"; echo ""; exit 0 ;;
            *) print_warn "Invalid option."; sleep 1 ;;
        esac
    done
}

# ── Block IPs ─────────────────────────────────────────────────────────────────
block_ips() {
    clear
    print_header

    if [[ -z "$IP_LIST" ]]; then
        print_error "IP list is empty. Cannot block."
        _press_enter; return
    fi

    local ip_count
    ip_count=$(echo "$IP_LIST" | wc -l)

    echo -e "  ${BOLD}Block Abuse IP-Ranges${RESET}"
    echo -e "  ${DIM}$ip_count ranges loaded from abuse-ips.ipv4${RESET}"
    echo ""

    local confirm
    confirm=$(ask "  Are you sure you want to block abuse IP-Ranges? [Y/n]: " "y")
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        print_warn "Cancelled."; _press_enter; return
    fi

    ensure_iptables
    ensure_chains

    local clear_rules
    clear_rules=$(ask "  Delete previous block rules before applying? [Y/n]: " "y")
    if [[ "$clear_rules" =~ ^[Yy] ]]; then
        iptables -F abuse-defender
    fi

    echo ""
    echo -e "  ${CYAN}Applying whitelist rules…${RESET}"

    # Whitelist localhost & RFC 1918
    iptables -I abuse-defender-whitelist -d 127.0.0.0/8    -j ACCEPT
    iptables -I abuse-defender-whitelist -d 10.0.0.0/8     -j ACCEPT
    iptables -I abuse-defender-whitelist -d 172.16.0.0/12  -j ACCEPT
    iptables -I abuse-defender-whitelist -d 192.168.0.0/16 -j ACCEPT

    # Link-local
    iptables -I abuse-defender-whitelist -d 169.254.0.0/16 -j ACCEPT

    # Server's own public IPs
    local my_ip
    for my_ip in $(hostname -I); do
        iptables -I abuse-defender-whitelist -d "$my_ip" -j ACCEPT
    done

    # DNS servers
    iptables -I abuse-defender-whitelist -d 1.1.1.2 -j ACCEPT
    iptables -I abuse-defender-whitelist -d 9.9.9.9 -j ACCEPT

    local whitelist_subnet=""
    if ! $NON_INTERACTIVE; then
        read -rp "  Enter additional subnet to whitelist (or leave blank to skip): " whitelist_subnet
    fi
    if [[ -n "$whitelist_subnet" ]]; then
        iptables -I abuse-defender-whitelist -d "$whitelist_subnet" -j ACCEPT
        print_status "Whitelisted $whitelist_subnet"
    fi

    echo ""
    echo -e "  ${CYAN}Blocking $ip_count abuse IP-Ranges…${RESET}"

    local ip count=0
    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        iptables -A abuse-defender -d "$ip" -j DROP
        (( count++ ))
    done <<< "$IP_LIST"

    # Block malicious domains via /etc/hosts
    local domain
    for domain in "${MALICIOUS_DOMAINS[@]}"; do
        grep -qxF "127.0.0.1 $domain" /etc/hosts || echo "127.0.0.1 $domain" >> /etc/hosts
    done

    save_rules

    echo ""
    print_status "Blocked $count IP ranges."
    echo ""
    _press_enter
}

# ── Whitelist IPs ─────────────────────────────────────────────────────────────
whitelist_ips() {
    clear
    print_header
    echo -e "  ${BOLD}Whitelist an IP / IP-Range${RESET}"
    echo ""
    read -rp "  Enter IP or range to whitelist (e.g. 192.168.1.0/24): " ip_range
    if [[ -z "$ip_range" ]]; then
        print_warn "No input provided."; _press_enter; return
    fi

    ensure_chains
    iptables -I abuse-defender-whitelist -d "$ip_range" -j ACCEPT
    save_rules

    echo ""
    print_status "$ip_range whitelisted."
    _press_enter
}

# ── Block custom IPs ──────────────────────────────────────────────────────────
block_custom_ips() {
    clear
    print_header
    echo -e "  ${BOLD}Block an IP / IP-Range${RESET}"
    echo ""
    read -rp "  Enter IP or range to block (e.g. 192.168.1.0/24): " ip_range
    if [[ -z "$ip_range" ]]; then
        print_warn "No input provided."; _press_enter; return
    fi

    ensure_chains
    iptables -A abuse-defender-custom -d "$ip_range" -j DROP
    save_rules

    echo ""
    print_status "$ip_range blocked."
    _press_enter
}

# ── View Rules ────────────────────────────────────────────────────────────────
view_rules() {
    clear
    print_header

    local chain
    for chain in abuse-defender abuse-defender-custom abuse-defender-whitelist; do
        echo -e "  ${BOLD}${CYAN}═══ $chain ═══${RESET}"
        iptables -L "$chain" -n --line-numbers 2>/dev/null || echo -e "  ${DIM}(chain not found)${RESET}"
        echo ""
    done

    _press_enter
}

# ── Clear all rules ───────────────────────────────────────────────────────────
clear_chain() {
    clear
    print_header
    echo -e "  ${BOLD}${RED}Clear all rules${RESET}"
    echo ""

    local confirm
    confirm=$(ask "  This will remove ALL abuse-defender rules. Continue? [y/N]: " "n")
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        print_warn "Cancelled."; _press_enter; return
    fi

    local chain
    for chain in abuse-defender abuse-defender-custom abuse-defender-whitelist; do
        iptables -F "$chain" 2>/dev/null || true
    done

    local domain
    for domain in "${MALICIOUS_DOMAINS[@]}"; do
        sed -i "/127\.0\.0\.1 $(printf '%s' "$domain" | sed 's/\./\\./g')/d" /etc/hosts
    done

    save_rules

    # Restore DNS backup if present
    if [[ -f /etc/systemd/resolved.conf.abuse-defender.bak ]]; then
        mv /etc/systemd/resolved.conf.abuse-defender.bak /etc/systemd/resolved.conf
        systemctl restart systemd-resolved 2>/dev/null
        print_status "systemd-resolved DNS restored."
    elif [[ -f /etc/resolv.conf.abuse-defender.bak ]]; then
        mv /etc/resolv.conf.abuse-defender.bak /etc/resolv.conf
        print_status "/etc/resolv.conf DNS restored."
    fi

    echo ""
    print_status "All rules cleared."
    _press_enter
}

# ── Setup DNS ─────────────────────────────────────────────────────────────────
setup_dns() {
    clear
    print_header
    echo -e "  ${BOLD}Setup DNS${RESET}"
    echo -e "  ${DIM}Primary: 1.1.1.2 (Cloudflare for Families)  |  Secondary: 9.9.9.9 (Quad9)${RESET}"
    echo ""

    # Whitelist DNS servers in firewall if chain exists
    if iptables -L abuse-defender-whitelist -n &>/dev/null; then
        iptables -I abuse-defender-whitelist -d 1.1.1.2 -j ACCEPT
        iptables -I abuse-defender-whitelist -d 9.9.9.9 -j ACCEPT
        save_rules
    fi

    if systemctl is-active --quiet systemd-resolved; then
        [[ ! -f /etc/systemd/resolved.conf.abuse-defender.bak ]] && \
            cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.abuse-defender.bak
        sed -i '/^DNS=/d; /^FallbackDNS=/d' /etc/systemd/resolved.conf
        printf "DNS=1.1.1.2 9.9.9.9\nFallbackDNS=1.1.1.2 9.9.9.9\n" >> /etc/systemd/resolved.conf
        systemctl restart systemd-resolved
        print_status "systemd-resolved configured and restarted."
    else
        [[ ! -f /etc/resolv.conf.abuse-defender.bak ]] && \
            cp /etc/resolv.conf /etc/resolv.conf.abuse-defender.bak 2>/dev/null
        chattr -i /etc/resolv.conf 2>/dev/null
        printf "nameserver 1.1.1.2\nnameserver 9.9.9.9\n" > /etc/resolv.conf
        print_status "/etc/resolv.conf updated."
    fi

    echo ""
    print_warn "Use option [5] (Clear all rules) to restore original DNS."
    echo ""
    _press_enter
}

# ── Entrypoint ────────────────────────────────────────────────────────────────
if $NON_INTERACTIVE; then
    clear
    print_header
    echo -e "  ${BOLD}Non-interactive mode — applying default setup${RESET}"
    echo ""
    block_ips
    setup_dns
    echo ""
    print_status "Default setup complete."
    exit 0
fi

main_menu
