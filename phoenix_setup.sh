#!/bin/bash

# ==============================================================================
# Phoenix Tunnel System Setup (Multi-Node & Management Support)
# Description: Automates the installation of Phoenix Server and Client.
#              Automatically installs Xray-core on Iran server for routing.
#              Provides tools to view, edit, delete tunnels, and fully uninstall.
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PHOENIX_DIR="/opt/phoenix"
XRAY_DIR="/usr/local/bin"
XRAY_CONF_DIR="/usr/local/etc/xray"
XRAY_CONFIG_FILE="$XRAY_CONF_DIR/config.json"

function check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run this script as root.${NC}"
        exit 1
    fi
}

function install_dependencies() {
    echo -e "${YELLOW}Installing required dependencies...${NC}"
    apt-get update -y -q > /dev/null 2>&1
    apt-get install -y -q wget unzip curl sshpass jq > /dev/null 2>&1
}

# ------------------------------------------------------------------------------
# XRAY ROUTING CONFIGURATION
# ------------------------------------------------------------------------------
function update_xray_config() {
    local conn_name=$1
    local local_socks_port=$2
    local panel_ports=$3

    echo "Updating Xray configuration ($conn_name)..."
    mkdir -p "$XRAY_DIR"
    mkdir -p "$XRAY_CONF_DIR"

    if [ ! -f "$XRAY_DIR/xray" ]; then
        echo "Downloading Xray-core..."
        wget -qO xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" > /dev/null 2>&1
        unzip -qo xray.zip xray -d "$XRAY_DIR"
        chmod +x "$XRAY_DIR/xray"
        rm xray.zip
    fi

    # Initialize basic config structure if it doesn't exist
    if [ ! -f "$XRAY_CONFIG_FILE" ]; then
        cat > "$XRAY_CONFIG_FILE" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }],
  "routing": { "domainStrategy": "AsIs", "rules": [] }
}
EOF
    fi

    # Remove existing rules for this connection if they exist (for edit mode)
    jq --arg name "in-$conn_name" --arg outname "out-$conn_name" \
       'del(.inbounds[] | select(.tag == $name)) | del(.outbounds[] | select(.tag == $outname)) | del(.routing.rules[] | select(.outboundTag == $outname))' \
       "$XRAY_CONFIG_FILE" > "${XRAY_CONFIG_FILE}.tmp" && mv "${XRAY_CONFIG_FILE}.tmp" "$XRAY_CONFIG_FILE"

    # Create new inbounds logic
    NEW_INBOUNDS="[]"
    IFS=',' read -ra ADDR <<< "$panel_ports"
    for i in "${!ADDR[@]}"; do
        port=$(echo "${ADDR[$i]}" | xargs)
        NEW_INBOUND=$(cat <<EOF
{
  "port": $port,
  "protocol": "dokodemo-door",
  "settings": { "address": "127.0.0.1", "port": $port, "network": "tcp,udp" },
  "tag": "in-$conn_name"
}
EOF
)
        NEW_INBOUNDS=$(echo "$NEW_INBOUNDS" | jq ". + [$NEW_INBOUND]")
    done

    # Create new outbound and rule
    NEW_OUTBOUND=$(cat <<EOF
{
  "protocol": "socks",
  "settings": { "servers": [{ "address": "127.0.0.1", "port": $local_socks_port }] },
  "tag": "out-$conn_name"
}
EOF
)

    NEW_RULE=$(cat <<EOF
{
  "type": "field",
  "inboundTag": ["in-$conn_name"],
  "outboundTag": "out-$conn_name"
}
EOF
)

    # Merge into config
    jq --argjson new_inbounds "$NEW_INBOUNDS" \
       --argjson new_outbound "$NEW_OUTBOUND" \
       --argjson new_rule "$NEW_RULE" \
       '.inbounds += $new_inbounds | .outbounds += [$new_outbound] | .routing.rules += [$new_rule]' \
       "$XRAY_CONFIG_FILE" > "${XRAY_CONFIG_FILE}.tmp" && mv "${XRAY_CONFIG_FILE}.tmp" "$XRAY_CONFIG_FILE"

    if [ ! -f "/etc/systemd/system/xray.service" ]; then
        echo "Creating Xray systemd service..."
        cat > "/etc/systemd/system/xray.service" <<EOF
[Unit]
Description=Xray Router Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$XRAY_DIR/xray run -config $XRAY_CONFIG_FILE
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable xray > /dev/null 2>&1
    fi

    systemctl restart xray
    echo -e "${GREEN}Xray router updated and restarted for $conn_name!${NC}"
}

# ------------------------------------------------------------------------------
# INSTALLATION FUNCTIONS
# ------------------------------------------------------------------------------
function install_server_manual() {
    echo -e "${GREEN}--- Setup Server Node (Foreign Server) ---${NC}"
    read -p "Enter a short name for this server (e.g., sweden, england): " CONN_NAME
    CONN_NAME=${CONN_NAME:-default}
    
    read -p "Enter Listen Port for this Phoenix Tunnel (Default: 2096): " TUNNEL_PORT
    TUNNEL_PORT=${TUNNEL_PORT:-2096}
    
    mkdir -p $PHOENIX_DIR && cd $PHOENIX_DIR
    if [ ! -f "phoenix-server" ]; then
        wget -qO phoenix-server.zip "https://github.com/Fox-Fig/phoenix/releases/latest/download/phoenix-server-linux-amd64.zip"
        unzip -qo phoenix-server.zip
        chmod +x phoenix-server
    fi
    
    echo "Generating keys..."
    ./phoenix-server -gen-keys > keys_$CONN_NAME.txt 2>&1
    mv private.key server_${CONN_NAME}.private.key
    SERVER_PUB_KEY=$(grep -A 1 'Public Key' keys_$CONN_NAME.txt | tail -n 1 | tr -d '\r')
    
    read -p "Enter the Client Public Key (leave empty if you don't have it yet): " CLIENT_PUB_KEY
    if [ -z "$CLIENT_PUB_KEY" ]; then
        AUTH_LINE="# authorized_clients = [ \"YOUR_CLIENT_PUB_KEY\" ]"
    else
        AUTH_LINE="authorized_clients = [ \"$CLIENT_PUB_KEY\" ]"
    fi

    cat > server_${CONN_NAME}.toml <<EOL
listen_addr = ":$TUNNEL_PORT"
[security]
enable_socks5 = true
enable_udp = false
enable_shadowsocks = false
enable_ssh = false
private_key = "server_${CONN_NAME}.private.key"
$AUTH_LINE
EOL

    cat > /etc/systemd/system/phoenix-server-${CONN_NAME}.service <<EOL
[Unit]
Description=Phoenix Server Service ($CONN_NAME)
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/phoenix
ExecStart=/opt/phoenix/phoenix-server -config server_${CONN_NAME}.toml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload && systemctl enable --now phoenix-server-${CONN_NAME} > /dev/null 2>&1
    
    echo -e "${GREEN}Server ($CONN_NAME) Installed!${NC}"
    echo -e "Your Server Public Key is: ${CYAN}$SERVER_PUB_KEY${NC}"
}

function install_client_manual() {
    echo -e "${GREEN}--- Setup Client Node (Iran Server) ---${NC}"
    read -p "Enter a short name for this connection (e.g., sweden, england): " CONN_NAME
    CONN_NAME=${CONN_NAME:-default}
    
    read -p "Enter Foreign Server IP: " FOREIGN_IP
    read -p "Enter Foreign Server Tunnel Port (e.g., 2096): " TUNNEL_PORT
    read -p "Enter Server Public Key: " SERVER_PUB_KEY
    read -p "Enter Local SOCKS5 Port for this connection (e.g., 1080): " LOCAL_SOCKS
    LOCAL_SOCKS=${LOCAL_SOCKS:-1080}
    
    mkdir -p $PHOENIX_DIR && cd $PHOENIX_DIR
    if [ ! -f "phoenix-client" ]; then
        wget -qO phoenix-client.zip "https://github.com/Fox-Fig/phoenix/releases/latest/download/phoenix-client-linux-amd64.zip"
        unzip -qo phoenix-client.zip
        chmod +x phoenix-client
    fi
    
    ./phoenix-client -gen-keys > client_keys_$CONN_NAME.txt 2>&1
    mv client_private.key client_${CONN_NAME}.private.key
    CLIENT_PUB_KEY=$(grep 'Public Key:' client_keys_$CONN_NAME.txt | awk '{print $3}')
    
    cat > client_${CONN_NAME}.toml <<EOL
remote_addr = "$FOREIGN_IP:$TUNNEL_PORT"
server_public_key = "$SERVER_PUB_KEY"
private_key = "client_${CONN_NAME}.private.key"

[[inbounds]]
protocol = "socks5"
local_addr = "127.0.0.1:$LOCAL_SOCKS"
enable_udp = true
EOL

    cat > /etc/systemd/system/phoenix-client-${CONN_NAME}.service <<EOL
[Unit]
Description=Phoenix Client Service ($CONN_NAME)
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/phoenix
ExecStart=/opt/phoenix/phoenix-client -config client_${CONN_NAME}.toml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload && systemctl enable --now phoenix-client-${CONN_NAME} > /dev/null 2>&1
    
    echo -e "${GREEN}Client ($CONN_NAME) Installed!${NC}"
    read -p "Install/Configure Xray-core routing globally for this connection? (y/n) " setup_xray
    if [[ "$setup_xray" == "y" || "$setup_xray" == "Y" ]]; then
       read -p "Enter the ports on Iran server you want to route to $CONN_NAME (comma-separated, e.g., 2096,2097): " PANEL_PORTS
       update_xray_config "$CONN_NAME" "$LOCAL_SOCKS" "$PANEL_PORTS"
    fi
}

function full_auto_install() {
    echo -e "${GREEN}--- Full-Auto Installation (Running from Iran Server) ---${NC}"
    read -p "Enter a short name for this connection (e.g., sweden, england): " CONN_NAME
    CONN_NAME=${CONN_NAME:-default}
    
    read -p "Enter Foreign Server IP: " FOREIGN_IP
    read -p "Enter Foreign Server SSH Port (Default: 22): " FOREIGN_PORT
    FOREIGN_PORT=${FOREIGN_PORT:-22}
    read -p "Enter Foreign Server Root Password: " FOREIGN_PASS
    read -p "Enter Phoenix Tunnel Port to use on remote (Default: 2096): " TUNNEL_PORT
    TUNNEL_PORT=${TUNNEL_PORT:-2096}
    read -p "Enter Local SOCKS5 Port for this link (e.g., 1080, 1081): " LOCAL_SOCKS
    LOCAL_SOCKS=${LOCAL_SOCKS:-1080}

    echo "Testing SSH connection..."
    if ! sshpass -p "$FOREIGN_PASS" ssh -n -o StrictHostKeyChecking=no -p $FOREIGN_PORT root@$FOREIGN_IP "echo 'SSH OK'" > /dev/null 2>&1; then
        echo -e "${RED}SSH Connection failed. Check credentials or use Manual Mode.${NC}"
        return
    fi

    mkdir -p $PHOENIX_DIR && cd $PHOENIX_DIR
    if [ ! -f "phoenix-client" ]; then
        wget -qO phoenix-client.zip "https://github.com/Fox-Fig/phoenix/releases/latest/download/phoenix-client-linux-amd64.zip" > /dev/null 2>&1
        unzip -qo phoenix-client.zip
        chmod +x phoenix-client
    fi
    ./phoenix-client -gen-keys > client_keys_$CONN_NAME.txt 2>&1
    mv client_private.key client_${CONN_NAME}.private.key
    CLIENT_PUB_KEY=$(grep 'Public Key:' client_keys_$CONN_NAME.txt | awk '{print $3}')

    echo -e "${YELLOW}Installing Server remotely (Foreign)...${NC}"
    SERVER_SCRIPT="
    apt-get update -y -q > /dev/null 2>&1
    apt-get install -y -q wget unzip > /dev/null 2>&1
    mkdir -p /opt/phoenix && cd /opt/phoenix
    if [ ! -f \"phoenix-server\" ]; then
        wget -qO phoenix-server.zip \"https://github.com/Fox-Fig/phoenix/releases/latest/download/phoenix-server-linux-amd64.zip\" > /dev/null 2>&1
        unzip -qo phoenix-server.zip
        chmod +x phoenix-server
    fi
    ./phoenix-server -gen-keys > server_keys_$CONN_NAME.txt 2>&1
    mv private.key server_${CONN_NAME}.private.key
    SERVER_PUB_KEY=\$(grep -A 1 'Public Key' server_keys_$CONN_NAME.txt | tail -n 1 | tr -d '\\r')
    
    cat > server_${CONN_NAME}.toml <<EOL
listen_addr = \":$TUNNEL_PORT\"
[security]
enable_socks5 = true
enable_udp = true
enable_shadowsocks = false
enable_ssh = false
private_key = \"server_${CONN_NAME}.private.key\"
authorized_clients = [ \"$CLIENT_PUB_KEY\" ]
EOL

    cat > /etc/systemd/system/phoenix-server-${CONN_NAME}.service <<EOL
[Unit]
Description=Phoenix Server Service ($CONN_NAME)
[Service]
ExecStart=/opt/phoenix/phoenix-server -config server_${CONN_NAME}.toml
Restart=on-failure
WorkingDirectory=/opt/phoenix
[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload && systemctl enable --now phoenix-server-${CONN_NAME} > /dev/null 2>&1
    "
    sshpass -p "$FOREIGN_PASS" ssh -n -o StrictHostKeyChecking=no -p $FOREIGN_PORT root@$FOREIGN_IP "$SERVER_SCRIPT"
    SERVER_PUB_KEY=$(sshpass -p "$FOREIGN_PASS" ssh -n -o StrictHostKeyChecking=no -p $FOREIGN_PORT root@$FOREIGN_IP "cat /opt/phoenix/server_keys_${CONN_NAME}.txt" | grep -A 1 'Public Key' | tail -n 1 | tr -d '\r')

    echo -e "${YELLOW}Configuring Client Locally (Iran)...${NC}"
    cat > client_${CONN_NAME}.toml <<EOL
remote_addr = "$FOREIGN_IP:$TUNNEL_PORT"
server_public_key = "$SERVER_PUB_KEY"
private_key = "client_${CONN_NAME}.private.key"

[[inbounds]]
protocol = "socks5"
local_addr = "127.0.0.1:$LOCAL_SOCKS"
enable_udp = true
EOL

    cat > /etc/systemd/system/phoenix-client-${CONN_NAME}.service <<EOL
[Unit]
Description=Phoenix Client Service ($CONN_NAME)
[Service]
ExecStart=/opt/phoenix/phoenix-client -config client_${CONN_NAME}.toml
Restart=on-failure
WorkingDirectory=/opt/phoenix
[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload && systemctl enable --now phoenix-client-${CONN_NAME} > /dev/null 2>&1

    echo -e "${GREEN}Phoenix Tunnel setup complete!${NC}"
    read -p "Install/Configure Xray-core routing globally for this connection? (y/n) " setup_xray
    if [[ "$setup_xray" == "y" || "$setup_xray" == "Y" ]]; then
       read -p "Enter the ports on Iran server you want to route to $CONN_NAME (comma-separated, e.g., 2096,2097): " PANEL_PORTS
       update_xray_config "$CONN_NAME" "$LOCAL_SOCKS" "$PANEL_PORTS"
    fi
}

# ------------------------------------------------------------------------------
# MANAGEMENT FUNCTIONS
# ------------------------------------------------------------------------------
function manage_tunnels() {
    echo -e "${CYAN}--- Manage Active Tunnels ---${NC}"
    # Find all phoenix services
    local services=($(ls /etc/systemd/system/ | grep 'phoenix-.*\.service$' | sed 's/\.service//'))
    
    if [ ${#services[@]} -eq 0 ]; then
        echo -e "${YELLOW}No Phoenix tunnels found on this server.${NC}"
        return
    fi
    
    echo "Active connections on this server:"
    for i in "${!services[@]}"; do
        echo "$((i+1))) ${services[$i]}"
    done
    
    read -p "Select a tunnel to manage (or 0 to cancel): " t_choice
    if [[ "$t_choice" -eq 0 || -z "${services[$((t_choice-1))]}" ]]; then
        return
    fi
    
    local selected_svc="${services[$((t_choice-1))]}"
    # Extract the connection name e.g., phoenix-client-sweden -> sweden
    local conn_name=$(echo "$selected_svc" | sed 's/phoenix-\(client\|server\)-//')
    
    echo -e "${CYAN}Managing: $selected_svc ($conn_name)${NC}"
    echo "1) Restart tunnel service"
    echo "2) Stop and disable tunnel service"
    echo "3) Edit Xray routing ports for this tunnel (Iran Server only)"
    echo "4) Delete this tunnel completely"
    read -p "Select an action: " a_choice
    
    case $a_choice in
        1)
            systemctl restart "$selected_svc"
            echo -e "${GREEN}Service restarted.${NC}"
            ;;
        2)
            systemctl stop "$selected_svc"
            systemctl disable "$selected_svc"
            echo -e "${YELLOW}Service stopped and disabled.${NC}"
            ;;
        3)
            if [ -f "$XRAY_CONFIG_FILE" ]; then
                read -p "Enter new ports to route to $conn_name (comma-separated): " NEW_PORTS
                # Get the local socks port from the existing client toml
                local SOCKS_PORT=$(grep "local_addr" "$PHOENIX_DIR/client_${conn_name}.toml" | cut -d':' -f3 | tr -d '"')
                if [ -n "$SOCKS_PORT" ] && [ -n "$NEW_PORTS" ]; then
                    update_xray_config "$conn_name" "$SOCKS_PORT" "$NEW_PORTS"
                    echo -e "${GREEN}Xray ports updated.${NC}"
                else
                    echo -e "${RED}Could not find existing SOCKS port for $conn_name, or no ports entered.${NC}"
                fi
            else
                echo -e "${RED}Xray configuration not found on this machine.${NC}"
            fi
            ;;
        4)
            echo -e "${RED}Are you sure you want to delete tunnel '$conn_name'? (y/n)${NC}"
            read -p "> " p_conf
            if [[ "$p_conf" == "y" || "$p_conf" == "Y" ]]; then
                systemctl stop "$selected_svc" > /dev/null 2>&1
                systemctl disable "$selected_svc" > /dev/null 2>&1
                rm -f /etc/systemd/system/"$selected_svc".service
                systemctl daemon-reload
                
                # Clean up Phoenix files
                rm -f "$PHOENIX_DIR/*${conn_name}*"
                
                # Clean up Xray rules if exists
                if [ -f "$XRAY_CONFIG_FILE" ]; then
                    jq --arg name "in-$conn_name" --arg outname "out-$conn_name" \
                       'del(.inbounds[] | select(.tag == $name)) | del(.outbounds[] | select(.tag == $outname)) | del(.routing.rules[] | select(.outboundTag == $outname))' \
                       "$XRAY_CONFIG_FILE" > "${XRAY_CONFIG_FILE}.tmp" && mv "${XRAY_CONFIG_FILE}.tmp" "$XRAY_CONFIG_FILE"
                    systemctl restart xray
                fi
                echo -e "${GREEN}Tunnel '$conn_name' deleted successfully.${NC}"
            fi
            ;;
        *)
            echo "Invalid action."
            ;;
    esac
}

function full_uninstall() {
    echo -e "${RED}--- FULL UNINSTALLATION ---${NC}"
    echo "WARNING: This will remove ALL Phoenix tunnels, keys, configurations, and the Xray router on this machine."
    read -p "Are you absolutely sure? Type 'YES' to confirm: " confirm
    
    if [ "$confirm" == "YES" ]; then
        echo "Stopping all related services..."
        # Stop all phoenix services
        for svc in $(ls /etc/systemd/system/ | grep 'phoenix-.*\.service$'); do
            systemctl stop $svc > /dev/null 2>&1
            systemctl disable $svc > /dev/null 2>&1
            rm -f /etc/systemd/system/$svc
        done
        
        # Stop Xray
        systemctl stop xray > /dev/null 2>&1
        systemctl disable xray > /dev/null 2>&1
        rm -f /etc/systemd/system/xray.service
        
        systemctl daemon-reload
        
        echo "Deleting directories..."
        rm -rf "$PHOENIX_DIR"
        rm -rf "$XRAY_CONF_DIR"
        rm -f "$XRAY_DIR/xray"
        
        echo -e "${GREEN}Uninstallation Complete. System is clean.${NC}"
    else
        echo -e "${YELLOW}Uninstallation aborted.${NC}"
    fi
}

# ------------------------------------------------------------------------------
# MAIN MENU
# ------------------------------------------------------------------------------
check_root
install_dependencies

while true; do
    echo -e "\n${CYAN}======================================================${NC}"
    echo -e "${GREEN}   Phoenix Tunnel Automation (Multi-Node Supported) ${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo "1) Setup First or Additional Server Node (Manually run on Foreign Server)"
    echo "2) Setup First or Additional Client Node (Manually run on Iran Server)"
    echo "3) Full-Auto (Run on Iran Server, configures both seamlessly)"
    echo "------------------------------------------------------"
    echo "4) Manage Active Tunnels (View, Edit Ports, Delete individual nodes)"
    echo "5) Full Uninstall (Clean everything off this machine)"
    echo "0) Exit"
    echo "------------------------------------------------------"
    if ! read -p "Select an option: " choice; then
        echo -e "\n${YELLOW}Input stream closed. Exiting.${NC}"
        break
    fi

    case $choice in
        1) install_server_manual ;;
        2) install_client_manual ;;
        3) full_auto_install ;;
        4) manage_tunnels ;;
        5) full_uninstall ;;
        0) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}" ;;
    esac
done
