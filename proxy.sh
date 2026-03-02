#!/bin/bash
# =============================================================================
# Server Proxy Script - Smart Port Detection & Diagnostics
# 
# Usage: source proxy.sh [on|off|status|test|check|help]
# 
# Priority for finding port:
# 1. .tunnel-mapping file (IP -> port)
# 2. config.yaml assigned_tunnel_port field
# 3. Default 11080
# 
# Features:
# - Auto-detects server IP and finds corresponding tunnel port
# - Pre-flight port connectivity check
# - Detailed diagnostics when connection fails
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAPPING_FILE="${SCRIPT_DIR}/.tunnel-mapping"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
DEFAULT_PORT=11080

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

get_server_ip() {
    local ip=""
    if command -v ip &>/dev/null; then
        ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    fi
    if [ -z "$ip" ]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    if [ -z "$ip" ] && command -v ifconfig &>/dev/null; then
        ip=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)
    fi
    echo "$ip"
}

find_port_from_mapping() {
    local server_ip="$1"
    local port=""
    
    # Priority 1: .tunnel-mapping file
    if [ -f "$MAPPING_FILE" ]; then
        port=$(grep "^${server_ip} " "$MAPPING_FILE" 2>/dev/null | awk '{print $2}')
        if [ -n "$port" ]; then
            echo "$port"
            return
        fi
    fi
    
    # Priority 2: config.yaml assigned_tunnel_port
    if [ -f "$CONFIG_FILE" ]; then
        local in_server=false
        local current_host=""
        while IFS= read -r line; do
            local trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')
            
            if [[ "$trimmed" =~ ^-?[[:space:]]*name: ]]; then
                in_server=true
                current_host=""
            fi
            
            if $in_server && [[ "$trimmed" =~ ^host:[[:space:]]*(.+)$ ]]; then
                current_host="${BASH_REMATCH[1]}"
            fi
            
            if $in_server && [ "$current_host" = "$server_ip" ] && [[ "$trimmed" =~ assigned_tunnel_port:[[:space:]]*([0-9]+) ]]; then
                port="${BASH_REMATCH[1]}"
                echo "$port"
                return
            fi
            
            if $in_server && [[ "$trimmed" =~ ^-?[[:space:]]*name: ]] && [ -n "$current_host" ] && [ "$current_host" != "$server_ip" ]; then
                in_server=false
            fi
        done < "$CONFIG_FILE"
    fi
    
    # Priority 3: Default
    echo "$DEFAULT_PORT"
}

check_port_available() {
    local port=$1
    local timeout_sec=3
    
    # Check if port is listening
    if command -v lsof &>/dev/null; then
        if lsof -i :$port &>/dev/null; then
            return 0  # Port is in use (good for tunnel)
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            return 0
        fi
    fi
    
    # Try to connect to the port
    if timeout $timeout_sec bash -c "echo > /dev/tcp/127.0.0.1/$port" 2>/dev/null; then
        return 0  # Can connect
    fi
    
    return 1  # Port not available
}

diagnose_port_issue() {
    local port=$1
    
    echo -e "${BLUE}=== Port Diagnostics ===${NC}"
    echo ""
    
    # Check if port is listening
    echo -e "${YELLOW}Checking port $port...${NC}"
    
    local pid=""
    if command -v lsof &>/dev/null; then
        pid=$(lsof -ti :$port 2>/dev/null)
        if [ -n "$pid" ]; then
            local cmd=$(ps -p $pid -o comm= 2>/dev/null)
            echo -e "  Port $port is used by: ${CYAN}$cmd (PID: $pid)${NC}"
        else
            echo -e "  ${RED}Port $port is not listening${NC}"
        fi
    elif command -v netstat &>/dev/null; then
        local info=$(netstat -tlnp 2>/dev/null | grep ":$port ")
        if [ -n "$info" ]; then
            echo -e "  Port $port: ${CYAN}$info${NC}"
        else
            echo -e "  ${RED}Port $port is not listening${NC}"
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}Common solutions:${NC}"
    echo -e "  1. ${CYAN}On Windows:${NC} Run: .\proxy.ps1 start"
    echo -e "  2. ${CYAN}On Windows:${NC} Run: .\proxy.ps1 fix"
    echo -e "  3. Check if Windows and server can SSH to each other"
    echo ""
}

show_help() {
    echo -e "${BLUE}=== Server Proxy Tool ===${NC}"
    echo ""
    echo -e "Usage: ${CYAN}source proxy.sh [command]${NC}"
    echo ""
    echo "Commands:"
    echo -e "  ${GREEN}on${NC}      - Enable proxy (with pre-flight check)"
    echo -e "  ${GREEN}off${NC}     - Disable proxy"
    echo -e "  ${GREEN}status${NC}  - Show status"
    echo -e "  ${GREEN}test${NC}    - Test connection"
    echo -e "  ${GREEN}check${NC}   - Check port availability"
    echo -e "  ${GREEN}help${NC}    - Show help"
    echo ""
    echo -e "${YELLOW}Port detection priority:${NC}"
    echo -e "  1. ${CYAN}.tunnel-mapping${NC} file"
    echo -e "  2. ${CYAN}config.yaml${NC} assigned_tunnel_port"
    echo -e "  3. Default ${CYAN}11080${NC}"
    echo ""
}

proxy_on() {
    local server_ip=$(get_server_ip)
    local tunnel_port=$(find_port_from_mapping "$server_ip")
    
    # Clean the port value
    tunnel_port=$(echo "$tunnel_port" | tr -cd '0-9')
    
    echo -e "${BLUE}=== Server Auto-Configuration ===${NC}"
    echo ""
    echo -e "Server IP:    ${CYAN}${server_ip}${NC}"
    echo -e "Tunnel Port:  ${CYAN}${tunnel_port}${NC}"
    
    # Pre-flight check
    echo ""
    echo -e "${YELLOW}Checking port connectivity...${NC}"
    if check_port_available "$tunnel_port"; then
        echo -e "  ${GREEN}âœ?Port ${tunnel_port} is ready${NC}"
    else
        echo -e "  ${RED}âœ?Port ${tunnel_port} is not accessible${NC}"
        echo ""
        diagnose_port_issue "$tunnel_port"
        return 1
    fi
    
    export http_proxy="http://127.0.0.1:${tunnel_port}"
    export https_proxy="http://127.0.0.1:${tunnel_port}"
    export HTTP_PROXY="${http_proxy}"
    export HTTPS_PROXY="${https_proxy}"
    
    echo ""
    echo -e "${GREEN}âœ?Proxy enabled${NC}"
    echo -e "  HTTP:  ${YELLOW}${http_proxy}${NC}"
    echo -e "  HTTPS: ${YELLOW}${https_proxy}${NC}"
    echo ""
    echo -e "${YELLOW}Note: Session only, will reset after logout${NC}"
    
    # Quick test
    echo ""
    echo -e "${YELLOW}Quick test...${NC}"
    local test_result=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -x "${http_proxy}" http://www.baidu.com 2>/dev/null)
    if [ "$test_result" = "200" ]; then
        echo -e "  ${GREEN}âœ?Connection OK (Baidu: HTTP 200)${NC}"
    else
        echo -e "  ${YELLOW}! Connection may have issues (HTTP $test_result)${NC}"
    fi
}

proxy_off() {
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
    echo -e "${GREEN}âœ?Proxy disabled${NC}"
}

proxy_status() {
    local server_ip=$(get_server_ip)
    local tunnel_port=$(find_port_from_mapping "$server_ip")
    tunnel_port=$(echo "$tunnel_port" | tr -cd '0-9')
    
    echo -e "${BLUE}=== Proxy Status ===${NC}"
    echo ""
    if [ -n "$http_proxy" ]; then
        echo -e "${GREEN}â—?Status: ENABLED${NC}"
        echo -e "  Proxy: ${YELLOW}${http_proxy}${NC}"
    else
        echo -e "${RED}â—?Status: DISABLED${NC}"
    fi
    echo ""
    echo -e "${BLUE}Auto-Detected:${NC}"
    echo -e "  Server IP:   ${CYAN}${server_ip}${NC}"
    echo -e "  Tunnel Port: ${CYAN}${tunnel_port}${NC}"
    
    # Check if port is actually working
    if check_port_available "$tunnel_port"; then
        echo -e "  Port Status: ${GREEN}Available${NC}"
    else
        echo -e "  Port Status: ${RED}Not Available${NC}"
    fi
    
    if [ -f "$MAPPING_FILE" ]; then
        echo -e "  Config File: ${CYAN}.tunnel-mapping${NC}"
    elif [ -f "$CONFIG_FILE" ]; then
        echo -e "  Config File: ${CYAN}config.yaml${NC}"
    fi
    echo ""
}

test_url() {
    local url=$1
    local desc=$2
    
    echo -e "${BLUE}Test: $desc${NC}"
    
    local result=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}" \
        --max-time 15 -x "${http_proxy}" "$url" 2>&1)
    local exit_code=$?
    
    local http_code=$(echo "$result" | cut -d'|' -f1)
    local time_total=$(echo "$result" | cut -d'|' -f2)
    
    if [ "$exit_code" -eq 0 ] && ([ "$http_code" = "200" ] || [ "$http_code" = "204" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]); then
        echo -e "  ${GREEN}âœ?OK${NC} (HTTP $http_code, ${time_total}s)"
        return 0
    else
        echo -e "  ${RED}âœ?Failed${NC} (HTTP $http_code)"
        return 1
    fi
}

proxy_test() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}       Connection Test                  ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    local server_ip=$(get_server_ip)
    local tunnel_port=$(find_port_from_mapping "$server_ip")
    tunnel_port=$(echo "$tunnel_port" | tr -cd '0-9')
    
    echo -e "${BLUE}Auto-Configuration:${NC}"
    echo -e "  Server IP:   ${CYAN}${server_ip}${NC}"
    echo -e "  Tunnel Port: ${CYAN}${tunnel_port}${NC}"
    echo ""
    
    # Check port first
    if ! check_port_available "$tunnel_port"; then
        diagnose_port_issue "$tunnel_port"
        return 1
    fi
    
    if [ -z "$http_proxy" ]; then
        echo -e "${YELLOW}Proxy not enabled. Enabling...${NC}"
        export http_proxy="http://127.0.0.1:${tunnel_port}"
        export https_proxy="http://127.0.0.1:${tunnel_port}"
        export HTTP_PROXY="${http_proxy}"
        export HTTPS_PROXY="${https_proxy}"
        echo ""
    fi
    
    echo -e "${YELLOW}>>> Testing via proxy${NC}"
    test_url "http://www.baidu.com" "Baidu"
    test_url "http://www.google.com" "Google"
    test_url "http://www.github.com" "GitHub"
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
}

proxy_check() {
    local server_ip=$(get_server_ip)
    local tunnel_port=$(find_port_from_mapping "$server_ip")
    tunnel_port=$(echo "$tunnel_port" | tr -cd '0-9')
    
    echo -e "${BLUE}=== Port Check ===${NC}"
    echo ""
    echo -e "Server IP:   ${CYAN}${server_ip}${NC}"
    echo -e "Tunnel Port: ${CYAN}${tunnel_port}${NC}"
    echo ""
    
    if check_port_available "$tunnel_port"; then
        echo -e "${GREEN}âœ?Port ${tunnel_port} is ready${NC}"
        echo -e "  You can now run: ${CYAN}source proxy.sh on${NC}"
    else
        diagnose_port_issue "$tunnel_port"
    fi
}

case "${1:-help}" in
    on)
        proxy_on
        ;;
    off)
        proxy_off
        ;;
    status)
        proxy_status
        ;;
    test)
        proxy_test
        ;;
    check)
        proxy_check
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        show_help
        ;;
esac
