#!/bin/bash

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/usr/local/etc/realm"
SERVICE_FILE="/etc/systemd/system/realm.service"
CONFIG_FILE="$CONFIG_DIR/realm.toml"
SCRIPT_NAME="realm-x"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}请以root权限运行此脚本${NC}"
        echo "使用: sudo $SCRIPT_NAME"
        exit 1
    fi
}

check_kernel_version() {
    KERNEL_VERSION=$(uname -r | cut -d. -f1,2)
    MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
    MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)
    
    if [ "$MAJOR" -gt 5 ] || ([ "$MAJOR" -eq 5 ] && [ "$MINOR" -gt 6 ]); then
        return 0
    else
        return 1
    fi
}

check_mptcp_enabled() {
    if [ -f "/proc/sys/net/mptcp/enabled" ]; then
        MPTCP_STATUS=$(cat /proc/sys/net/mptcp/enabled)
        if [ "$MPTCP_STATUS" = "1" ]; then
            return 0
        fi
    fi
    return 1
}

enable_mptcp() {
    echo "启用MPTCP功能..."
    
    local config_success=false
    
    if [ -w "/etc/sysctl.conf" ] || touch /etc/sysctl.conf 2>/dev/null; then
        if ! grep -q "net.mptcp.enabled" /etc/sysctl.conf 2>/dev/null; then
            echo "net.mptcp.enabled=1" >> /etc/sysctl.conf && config_success=true
            echo -e "${GREEN}已在/etc/sysctl.conf中添加MPTCP配置${NC}"
        else
            sed -i 's/^net.mptcp.enabled=.*/net.mptcp.enabled=1/' /etc/sysctl.conf && config_success=true
            echo -e "${GREEN}已更新/etc/sysctl.conf中的MPTCP配置${NC}"
        fi
    fi

    if [ "$config_success" = false ] && [ -d "/etc/sysctl.d" ]; then
        echo "net.mptcp.enabled=1" > /etc/sysctl.d/99-mptcp.conf 2>/dev/null && {
            config_success=true
            echo -e "${GREEN}已在/etc/sysctl.d/99-mptcp.conf中添加MPTCP配置${NC}"
        }
    fi
    
    if [ "$config_success" = false ]; then
        echo -e "${RED}警告：无法写入MPTCP配置文件，配置可能在重启后失效${NC}"
    fi
    
    sysctl -p > /dev/null 2>&1 || sysctl --system > /dev/null 2>&1 || {
        echo -e "${YELLOW}sysctl命令执行失败，尝试直接设置${NC}"
        echo 1 > /proc/sys/net/mptcp/enabled 2>/dev/null || true
    }
    
    if check_mptcp_enabled; then
        if [ "$config_success" = true ]; then
            echo -e "${GREEN}MPTCP功能已成功启用并已永久保存${NC}"
        else
            echo -e "${YELLOW}MPTCP功能已启用但可能在重启后失效${NC}"
        fi
        return 0
    else
        echo -e "${RED}MPTCP功能启用失败，请检查系统支持${NC}"
        return 1
    fi
}

version_compare() {
    local version1="$1"
    local version2="$2"
    
    version1=${version1#v}
    version2=${version2#v}
    
    local higher_version=$(printf '%s\n%s\n' "$version1" "$version2" | sort -V | tail -n1)
    
    if [ "$version1" = "$higher_version" ]; then
        return 0
    else
        return 1
    fi
}

check_and_configure_mptcp() {
    local version="$1"
    
    if version_compare "$version" "2.8.0"; then
        echo -e "${BLUE}检测到Realm版本 $version 支持MPTCP功能${NC}"
        
        if check_kernel_version; then
            KERNEL_VERSION=$(uname -r)
            echo -e "${GREEN}内核版本 $KERNEL_VERSION 支持MPTCP${NC}"
            
            if ! check_mptcp_enabled; then
                echo -e "${YELLOW}MPTCP功能未启用，正在配置...${NC}"
                enable_mptcp
            else
                echo -e "${GREEN}MPTCP功能已启用${NC}"
            fi
            
            return 0
        else
            KERNEL_VERSION=$(uname -r)
            echo -e "${YELLOW}当前内核版本 $KERNEL_VERSION 不支持MPTCP（需要>5.6）${NC}"
            return 1
        fi
    else
        return 1
    fi
}

create_config_with_mptcp() {
    local supports_mptcp="$1"
    
    if [ "$supports_mptcp" = "true" ]; then
        cat > "$CONFIG_FILE" << EOF
[network]
no_tcp = false
use_udp = true
send_mptcp = false
accept_mptcp = false

EOF
    else
        cat > "$CONFIG_FILE" << EOF
[network]
no_tcp = false
use_udp = true

EOF
    fi
}

update_config_with_mptcp() {
    if [ -f "$CONFIG_FILE" ]; then
        if ! grep -q "send_mptcp\|accept_mptcp" "$CONFIG_FILE"; then
            sed -i '/^\[network\]/,/^$/s/use_udp = true/use_udp = true\nsend_mptcp = false\naccept_mptcp = false/' "$CONFIG_FILE"
            echo -e "${GREEN}已在现有配置文件中添加MPTCP支持${NC}"
        fi
    fi
}

manage_mptcp() {
    check_root
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}配置文件不存在: $CONFIG_FILE${NC}"
        return
    fi
    
    if ! grep -q "send_mptcp\|accept_mptcp" "$CONFIG_FILE"; then
        echo -e "${YELLOW}当前配置文件不支持MPTCP功能${NC}"
        return
    fi
    
    echo -e "${BLUE}当前MPTCP配置状态:${NC}"
    echo "------------------------------------"
    
    SEND_MPTCP=$(grep "send_mptcp" "$CONFIG_FILE" | grep -o "true\|false")
    ACCEPT_MPTCP=$(grep "accept_mptcp" "$CONFIG_FILE" | grep -o "true\|false")
    
    echo "send_mptcp: $SEND_MPTCP"
    echo "accept_mptcp: $ACCEPT_MPTCP"
    
    if check_mptcp_enabled; then
        echo -e "系统MPTCP状态: ${GREEN}已启用${NC}"
    else
        echo -e "系统MPTCP状态: ${RED}未启用${NC}"
    fi
    
    echo "------------------------------------"
    
    echo "MPTCP管理选项:"
    echo "1. 启用MPTCP (send_mptcp=true, accept_mptcp=true)"
    echo "2. 禁用MPTCP (send_mptcp=false, accept_mptcp=false)"
    echo "3. 仅启用发送 (send_mptcp=true, accept_mptcp=false)"
    echo "4. 仅启用接收 (send_mptcp=false, accept_mptcp=true)"
    echo "5. 返回主菜单"
    
    read -p "请选择 [1-5]: " mptcp_choice
    
    case $mptcp_choice in
        1)
            sed -i 's/send_mptcp = false/send_mptcp = true/' "$CONFIG_FILE"
            sed -i 's/accept_mptcp = false/accept_mptcp = true/' "$CONFIG_FILE"
            echo -e "${GREEN}已启用MPTCP功能${NC}"
            ;;
        2)
            sed -i 's/send_mptcp = true/send_mptcp = false/' "$CONFIG_FILE"
            sed -i 's/accept_mptcp = true/accept_mptcp = false/' "$CONFIG_FILE"
            echo -e "${YELLOW}已禁用MPTCP功能${NC}"
            ;;
        3)
            sed -i 's/send_mptcp = false/send_mptcp = true/' "$CONFIG_FILE"
            sed -i 's/accept_mptcp = true/accept_mptcp = false/' "$CONFIG_FILE"
            echo -e "${GREEN}已启用MPTCP发送功能${NC}"
            ;;
        4)
            sed -i 's/send_mptcp = true/send_mptcp = false/' "$CONFIG_FILE"
            sed -i 's/accept_mptcp = false/accept_mptcp = true/' "$CONFIG_FILE"
            echo -e "${GREEN}已启用MPTCP接收功能${NC}"
            ;;
        5)
            return
            ;;
        *)
            echo -e "${RED}无效的选择${NC}"
            return
            ;;
    esac
    
    read -p "是否重启realm服务以应用更改? (y/n): " restart_service
    if [[ "$restart_service" =~ ^[Yy]$ ]]; then
        if systemctl is-active --quiet realm; then
            systemctl restart realm
            echo -e "${GREEN}服务已重启${NC}"
        else
            systemctl start realm
            echo -e "${GREEN}服务已启动${NC}"
        fi
    fi
}

check_installation() {
    if [ -f "$INSTALL_DIR/realm" ] && [ -f "$CONFIG_FILE" ]; then
        return 0
    else
        return 1
    fi
}

add_new_forwarding() {
    check_root
    read -p "请输入本地监听端口: " LOCAL_PORT
    read -p "请输入远程目标地址(IP或域名): " REMOTE_TARGET
    read -p "请输入远程目标端口: " REMOTE_PORT
    
    MPTCP_SUPPORTED=false
    if grep -q "send_mptcp\|accept_mptcp" "$CONFIG_FILE" 2>/dev/null; then
        MPTCP_SUPPORTED=true
    fi

    ENABLE_MPTCP=false
    if [ "$MPTCP_SUPPORTED" = "true" ]; then
        read -p "是否启用MPTCP支持? (y/n): " USE_MPTCP
        if [[ "$USE_MPTCP" =~ ^[Yy]$ ]]; then
            ENABLE_MPTCP=true
            sed -i 's/send_mptcp = false/send_mptcp = true/' "$CONFIG_FILE"
            sed -i 's/accept_mptcp = false/accept_mptcp = true/' "$CONFIG_FILE"
            echo -e "${GREEN}已启用全局MPTCP支持${NC}"
        fi
    fi

    if [[ "$REMOTE_TARGET" =~ : ]]; then
        if [[ ! "$REMOTE_TARGET" =~ ^\[.*\]$ ]]; then
            REMOTE_TARGET="[$REMOTE_TARGET]"
        fi
    fi

    read -p "是否配置加密隧道? (y/n): " USE_ENCRYPTION
    ENCRYPTION_CONFIG=""
    
    if [[ "$USE_ENCRYPTION" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}请选择加密隧道类型:${NC}"
        echo "1. TLS"
        echo "2. WebSocket (WS)"
        echo "3. WebSocket + TLS (WSS)"
        read -p "请选择 [1-3]: " ENCRYPTION_TYPE
        
        case $ENCRYPTION_TYPE in
            1) # TLS
                read -p "请输入 SNI 域名: " SNI_DOMAIN
                read -p "是否开启 insecure 选项? (y/n): " USE_INSECURE
                
                if [[ "$USE_INSECURE" =~ ^[Yy]$ ]]; then
                    ENCRYPTION_CONFIG="tls;sni=$SNI_DOMAIN;insecure"
                else
                    ENCRYPTION_CONFIG="tls;servername=$SNI_DOMAIN"
                fi
                ;;
            2) # WS
                read -p "请输入 Host 域名: " WS_HOST
                read -p "请输入 Path (默认为/wechat): " WS_PATH
                if [ -z "$WS_PATH" ]; then
                    WS_PATH="/wechat"
                fi
                ENCRYPTION_CONFIG="ws;host=$WS_HOST;path=$WS_PATH"
                ;;
            3) # WSS
                read -p "是否开启 insecure 选项? (y/n): " USE_INSECURE
                read -p "请输入 Host 域名: " WS_HOST
                read -p "请输入 Path (默认为/wechat): " WS_PATH
                read -p "请输入 SNI 域名: " SNI_DOMAIN
                
                if [ -z "$WS_PATH" ]; then
                    WS_PATH="/wechat"
                fi
                
                if [[ "$USE_INSECURE" =~ ^[Yy]$ ]]; then
                    ENCRYPTION_CONFIG="ws;host=$WS_HOST;path=$WS_PATH;tls;sni=$SNI_DOMAIN;insecure"
                else
                    ENCRYPTION_CONFIG="ws;host=$WS_HOST;path=$WS_PATH;tls;servername=$SNI_DOMAIN"
                fi
                ;;
            *)
                echo -e "${RED}无效的选择，将不使用加密隧道${NC}"
                ;;
        esac
    fi

    if [ -n "$ENCRYPTION_CONFIG" ]; then
        echo -e "\n[[endpoints]]\nlisten = \"0.0.0.0:${LOCAL_PORT}\"\nremote = \"${REMOTE_TARGET}:${REMOTE_PORT}\"\nremote_transport = \"${ENCRYPTION_CONFIG}\"" >> "$CONFIG_FILE"
        echo -e "${GREEN}已添加新的加密转发规则: 0.0.0.0:${LOCAL_PORT} -> ${REMOTE_TARGET}:${REMOTE_PORT} (加密类型: ${ENCRYPTION_CONFIG})${NC}"
    else
        echo -e "\n[[endpoints]]\nlisten = \"0.0.0.0:${LOCAL_PORT}\"\nremote = \"${REMOTE_TARGET}:${REMOTE_PORT}\"" >> "$CONFIG_FILE"
        echo -e "${GREEN}已添加新的转发规则: 0.0.0.0:${LOCAL_PORT} -> ${REMOTE_TARGET}:${REMOTE_PORT}${NC}"
    fi

    if [ "$ENABLE_MPTCP" = "true" ]; then
        echo -e "${GREEN}转发规则已启用MPTCP支持${NC}"
    fi

    if systemctl is-active --quiet realm; then
        echo "重启realm服务..."
        systemctl restart realm
        echo -e "${GREEN}服务已重启${NC}"
    else
        echo "realm服务未运行，正在启动..."
        systemctl start realm
        echo -e "${GREEN}服务已启动${NC}"
    fi
}

delete_forwarding() {
    check_root
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}配置文件不存在: $CONFIG_FILE${NC}"
        return
    fi
    
    echo -e "${BLUE}当前转发规则:${NC}"
    echo "------------------------------------"
    
    RULES=$(awk '
    BEGIN { count = 0; endpoint_start = 0; }
    /\[\[endpoints\]\]/ { 
      endpoint_start = NR;
      endpoints[count] = endpoint_start;
      count++;
    }
    /listen =/ { 
      gsub(/"/, "", $3);
      listen[count-1] = $3;
    }
    /remote =/ { 
      gsub(/"/, "", $3);
      remote[count-1] = $3;
    }
    /remote_transport =/ { 
      gsub(/"/, "", $3);
      transport[count-1] = $3;
    }
    END {
      for (i = 0; i < count; i++) {
        if (transport[i]) {
          print i " : " listen[i] " -> " remote[i] " (加密: " transport[i] ")";
        } else {
          print i " : " listen[i] " -> " remote[i];
        }
        print endpoints[i];
      }
    }' "$CONFIG_FILE")
    
    if [ -z "$RULES" ]; then
        echo "没有找到转发规则"
        return
    fi
    
    RULE_COUNT=$(echo "$RULES" | awk 'NR % 2 == 1 {count++} END {print count}')
    
    if [ "$RULE_COUNT" -eq 0 ]; then
        echo "没有找到转发规则"
        return
    fi
    
    DISPLAY_RULES=$(echo "$RULES" | awk 'NR % 2 == 1 {print}')
    RULE_LINES=$(echo "$RULES" | awk 'NR % 2 == 0 {print}')
    
    echo "$DISPLAY_RULES"
    echo "------------------------------------"
    
    read -p "请输入要删除的规则序号 [0-$((RULE_COUNT-1))]: " RULE_NUM
    
    if ! [[ "$RULE_NUM" =~ ^[0-9]+$ ]] || [ "$RULE_NUM" -ge "$RULE_COUNT" ]; then
        echo -e "${RED}无效的规则序号${NC}"
        return
    fi
    
    LINE_NUM=$(echo "$RULE_LINES" | sed -n "$((RULE_NUM+1))p")
    
    START_LINE=$LINE_NUM
    
    if [ "$RULE_NUM" -lt "$((RULE_COUNT-1))" ]; then
        NEXT_LINE=$(echo "$RULE_LINES" | sed -n "$((RULE_NUM+2))p")
        END_LINE=$((NEXT_LINE-1))
    else
        END_LINE=$(wc -l < "$CONFIG_FILE")
    fi
    
    TEMP_CONFIG=$(mktemp)
    
    if [ "$START_LINE" -gt 1 ]; then
        head -n $((START_LINE-1)) "$CONFIG_FILE" > "$TEMP_CONFIG"
    else
        > "$TEMP_CONFIG"
    fi
    
    if [ "$END_LINE" -lt "$(wc -l < "$CONFIG_FILE")" ]; then
        tail -n $(($(wc -l < "$CONFIG_FILE") - END_LINE)) "$CONFIG_FILE" >> "$TEMP_CONFIG"
    fi
    
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    
    mv "$TEMP_CONFIG" "$CONFIG_FILE"
    
    echo -e "${GREEN}已删除规则序号 $RULE_NUM${NC}"
    
    if systemctl is-active --quiet realm; then
        echo "重启realm服务..."
        systemctl restart realm
        echo -e "${GREEN}服务已重启${NC}"
    else
        echo "realm服务未运行，正在启动..."
        systemctl start realm
        echo -e "${GREEN}服务已启动${NC}"
    fi
}

uninstall_realm() {
    check_root
    echo -e "${YELLOW}正在卸载Realm...${NC}"
    
    if systemctl is-active --quiet realm; then
        echo "停止realm服务..."
        systemctl stop realm
    fi
    
    if systemctl is-enabled --quiet realm; then
        echo "禁用realm服务..."
        systemctl disable realm
    fi
    
    if [ -f "$SERVICE_FILE" ]; then
        echo "删除服务文件..."
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi
    
    if [ -f "$INSTALL_DIR/realm" ]; then
        echo "删除二进制文件..."
        rm -f "$INSTALL_DIR/realm"
    fi
    
    read -p "是否删除配置文件? (y/n): " REMOVE_CONFIG
    if [[ "$REMOVE_CONFIG" =~ ^[Yy]$ ]]; then
        echo "删除配置目录..."
        rm -rf "$CONFIG_DIR"
    else
        echo "保留配置文件，位置: $CONFIG_DIR"
    fi
    
    echo "删除realm-x命令..."
    
    TEMP_SCRIPT=$(mktemp)
    cat > "$TEMP_SCRIPT" << 'EOF'
sleep 1
rm -f "/usr/local/bin/realm-x"
rm -f "$0"
EOF
    
    chmod +x "$TEMP_SCRIPT"
    
    echo -e "${GREEN}Realm 已成功卸载${NC}"
    echo "realm-x命令将在退出后删除"
    
    nohup "$TEMP_SCRIPT" > /dev/null 2>&1 &
    
    exit 0
}

perform_installation() {
    check_root
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR" || exit 1

    echo "获取最新版本..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/zhboner/realm/releases/latest | grep "tag_name" | cut -d '"' -f 4)

    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${YELLOW}无法获取最新版本，使用默认版本 v2.7.0${NC}"
        LATEST_VERSION="v2.7.0"
    fi

    echo -e "${GREEN}最新版本: $LATEST_VERSION${NC}"
    
    MPTCP_SUPPORTED=false
    if check_and_configure_mptcp "$LATEST_VERSION"; then
        MPTCP_SUPPORTED=true
    fi

    DOWNLOAD_URL="https://github.com/zhboner/realm/releases/download/${LATEST_VERSION}"
    get_arch() {
        ARCH=$(uname -m)
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        
        case "$ARCH" in
            x86_64)
                case "$OS" in
                    linux)
                        if [ -f "/etc/alpine-release" ]; then
                            echo "x86_64-unknown-linux-musl"
                        else
                            echo "x86_64-unknown-linux-gnu"
                        fi
                        ;;
                    darwin)
                        echo "x86_64-apple-darwin"
                        ;;
                    msys*|mingw*|cygwin*)
                        echo "x86_64-pc-windows-msvc"
                        ;;
                    *)
                        echo "unsupported"
                        ;;
                esac
                ;;
            aarch64|arm64)
                case "$OS" in
                    linux)
                        if [ -f "/etc/alpine-release" ]; then
                            echo "aarch64-unknown-linux-musl"
                        else
                            echo "aarch64-unknown-linux-gnu"
                        fi
                        ;;
                    darwin)
                        echo "aarch64-apple-darwin"
                        ;;
                    android)
                        echo "aarch64-linux-android"
                        ;;
                    *)
                        echo "unsupported"
                        ;;
                esac
                ;;
            armv7*)
                if [ -f "/etc/alpine-release" ]; then
                    echo "armv7-unknown-linux-musleabihf"
                else
                    echo "armv7-unknown-linux-gnueabihf"
                fi
                ;;
            arm*)
                if [ -f "/etc/alpine-release" ]; then
                    echo "arm-unknown-linux-musleabihf"
                else
                    echo "arm-unknown-linux-gnueabihf"
                fi
                ;;
            *)
                echo "unsupported"
                ;;
        esac
    }

    CURRENT_ARCH=$(get_arch)

    if [ "$CURRENT_ARCH" = "unsupported" ]; then
        echo -e "${RED}不支持的系统架构${NC}"
        exit 1
    fi

    echo "检测到系统架构: $CURRENT_ARCH"
    FILENAME="realm-${CURRENT_ARCH}.tar.gz"
    DOWNLOAD_LINK="${DOWNLOAD_URL}/${FILENAME}"

    echo "开始下载 $DOWNLOAD_LINK"
    if command -v curl &>/dev/null; then
        curl -L -o "$FILENAME" "$DOWNLOAD_LINK"
    elif command -v wget &>/dev/null; then
        wget -O "$FILENAME" "$DOWNLOAD_LINK"
    else
        echo -e "${RED}需要安装curl或wget${NC}"
        exit 1
    fi

    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败${NC}"
        exit 1
    fi

    echo "下载完成，开始解压"
    tar -xzf "$FILENAME"

    if [ -d "$INSTALL_DIR" ] && [ -w "$INSTALL_DIR" ]; then
        echo "将realm二进制文件安装到 $INSTALL_DIR"
        cp realm "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/realm"
        REALM_PATH="$INSTALL_DIR/realm"
    else
        echo -e "${YELLOW}目录 $INSTALL_DIR 不存在或没有写入权限，将文件保存在当前目录${NC}"
        chmod +x realm
        REALM_PATH="$PWD/realm"
        INSTALL_DIR="$PWD"
        CONFIG_DIR="$PWD/realm_config"
        SERVICE_FILE="$PWD/realm.service"
        CONFIG_FILE="$CONFIG_DIR/realm.toml"
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "配置文件不存在，将创建基本配置..."
        
        if [ -d "$CONFIG_DIR" ] || mkdir -p "$CONFIG_DIR"; then
            echo "创建配置文件 $CONFIG_FILE"
            create_config_with_mptcp "$MPTCP_SUPPORTED"
        else
            echo -e "${YELLOW}无法创建配置目录 $CONFIG_DIR${NC}"
            CONFIG_DIR="$PWD"
            CONFIG_FILE="$CONFIG_DIR/realm.toml"
            create_config_with_mptcp "$MPTCP_SUPPORTED"
        fi
        
        echo -e "${YELLOW}请在安装完成后使用 'realm-x -a' 命令添加转发规则${NC}"
    else
        echo "检测到已存在配置文件，保留现有配置"
        if [ "$MPTCP_SUPPORTED" = "true" ]; then
            update_config_with_mptcp
        fi
    fi

    if [ "$MPTCP_SUPPORTED" = "true" ]; then
        echo -e "${GREEN}此版本支持MPTCP功能，您可以使用 'realm-x --mptcp' 管理MPTCP设置${NC}"
    fi

    if [ -d "/etc/systemd/system" ] && [ -w "/etc/systemd/system" ]; then
        echo "创建systemd服务文件 $SERVICE_FILE"
        cat > "$SERVICE_FILE" << EOF
[Unit]
Description=realm
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=always
RestartSec=5s
DynamicUser=true
ExecStart=$REALM_PATH -c $CONFIG_FILE

[Install]
WantedBy=multi-user.target
EOF

        echo "启用并启动服务"
        systemctl daemon-reload
        systemctl enable realm
        systemctl start realm
        
        echo -e "${GREEN}realm服务已安装并启动${NC}"
        echo "配置文件位置: $CONFIG_FILE"
        echo "服务状态: $(systemctl status realm | grep Active)"
    else
        echo -e "${YELLOW}无法创建systemd服务文件，请手动配置启动项${NC}"
        cat > "$SERVICE_FILE" << EOF
[Unit]
Description=realm
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=always
RestartSec=5s
DynamicUser=true
ExecStart=$REALM_PATH -c $CONFIG_FILE

[Install]
WantedBy=multi-user.target
EOF
        echo "服务文件已保存到 $SERVICE_FILE"
    fi

    install_command

    echo "清理临时文件"
    rm -f "$FILENAME"
    cd - > /dev/null
    rm -rf "$TMP_DIR"

    echo -e "${GREEN}Realm 安装完成${NC}"
    echo "二进制文件位置: $REALM_PATH"
    echo "配置文件位置: $CONFIG_FILE"
    echo -e "${GREEN}您现在可以使用 'realm-x -a' 命令添加转发规则${NC}"
}

install_command() {
    check_root
    echo "安装realm-x命令..."
    
    cat > "$SCRIPT_PATH" << 'REALMX_SCRIPT'
#!/bin/bash
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/usr/local/etc/realm"
SERVICE_FILE="/etc/systemd/system/realm.service"
CONFIG_FILE="$CONFIG_DIR/realm.toml"
SCRIPT_NAME="realm-x"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}请以root权限运行此脚本${NC}"
        echo "使用: sudo $SCRIPT_NAME"
        exit 1
    fi
}

check_installation() {
    if [ -f "$INSTALL_DIR/realm" ] && [ -f "$CONFIG_FILE" ]; then
        return 0
    else
        return 1
    fi
}

check_kernel_version() {
    KERNEL_VERSION=$(uname -r | cut -d. -f1,2)
    MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
    MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)
    
    if [ "$MAJOR" -gt 5 ] || ([ "$MAJOR" -eq 5 ] && [ "$MINOR" -gt 6 ]); then
        return 0
    else
        return 1
    fi
}

check_mptcp_enabled() {
    if [ -f "/proc/sys/net/mptcp/enabled" ]; then
        MPTCP_STATUS=$(cat /proc/sys/net/mptcp/enabled)
        if [ "$MPTCP_STATUS" = "1" ]; then
            return 0
        fi
    fi
    return 1
}

enable_mptcp() {
    echo "启用MPTCP功能..."
    
    # 尝试多种方式确保配置持久化
    local config_success=false
    
    # 方法1: 使用/etc/sysctl.conf
    if [ -w "/etc/sysctl.conf" ] || touch /etc/sysctl.conf 2>/dev/null; then
        if ! grep -q "net.mptcp.enabled" /etc/sysctl.conf 2>/dev/null; then
            echo "net.mptcp.enabled=1" >> /etc/sysctl.conf && config_success=true
            echo -e "${GREEN}已在/etc/sysctl.conf中添加MPTCP配置${NC}"
        else
            sed -i 's/^net.mptcp.enabled=.*/net.mptcp.enabled=1/' /etc/sysctl.conf && config_success=true
            echo -e "${GREEN}已更新/etc/sysctl.conf中的MPTCP配置${NC}"
        fi
    fi
    
    # 方法2: 如果方法1失败，尝试使用/etc/sysctl.d/
    if [ "$config_success" = false ] && [ -d "/etc/sysctl.d" ]; then
        echo "net.mptcp.enabled=1" > /etc/sysctl.d/99-mptcp.conf 2>/dev/null && {
            config_success=true
            echo -e "${GREEN}已在/etc/sysctl.d/99-mptcp.conf中添加MPTCP配置${NC}"
        }
    fi
    
    if [ "$config_success" = false ]; then
        echo -e "${RED}警告：无法写入MPTCP配置文件，配置可能在重启后失效${NC}"
    fi
    
    # 立即应用配置
    sysctl -p > /dev/null 2>&1 || sysctl --system > /dev/null 2>&1 || {
        echo -e "${YELLOW}sysctl命令执行失败，尝试直接设置${NC}"
        echo 1 > /proc/sys/net/mptcp/enabled 2>/dev/null || true
    }
    
    # 验证配置是否生效
    if check_mptcp_enabled; then
        if [ "$config_success" = true ]; then
            echo -e "${GREEN}MPTCP功能已成功启用并已永久保存${NC}"
        else
            echo -e "${YELLOW}MPTCP功能已启用但可能在重启后失效${NC}"
        fi
        return 0
    else
        echo -e "${RED}MPTCP功能启用失败，请检查系统支持${NC}"
        return 1
    fi
}

version_compare() {
    local version1="$1"
    local version2="$2"
    
    version1=${version1#v}
    version2=${version2#v}
    
    local higher_version=$(printf '%s\n%s\n' "$version1" "$version2" | sort -V | tail -n1)
    
    if [ "$version1" = "$higher_version" ]; then
        return 0
    else
        return 1
    fi
}

check_and_configure_mptcp() {
    local version="$1"
    
    if version_compare "$version" "2.8.0"; then
        echo -e "${BLUE}检测到Realm版本 $version 支持MPTCP功能${NC}"
        
        if check_kernel_version; then
            KERNEL_VERSION=$(uname -r)
            echo -e "${GREEN}内核版本 $KERNEL_VERSION 支持MPTCP${NC}"
            
            if ! check_mptcp_enabled; then
                echo -e "${YELLOW}MPTCP功能未启用，正在配置...${NC}"
                enable_mptcp
            else
                echo -e "${GREEN}MPTCP功能已启用${NC}"
            fi
            
            return 0
        else
            KERNEL_VERSION=$(uname -r)
            echo -e "${YELLOW}当前内核版本 $KERNEL_VERSION 不支持MPTCP（需要>5.6）${NC}"
            return 1
        fi
    else
        return 1
    fi
}

create_config_with_mptcp() {
    local supports_mptcp="$1"
    
    if [ "$supports_mptcp" = "true" ]; then
        cat > "$CONFIG_FILE" << EOF
[network]
no_tcp = false
use_udp = true
send_mptcp = false
accept_mptcp = false

EOF
    else
        cat > "$CONFIG_FILE" << EOF
[network]
no_tcp = false
use_udp = true

EOF
    fi
}

update_config_with_mptcp() {
    if [ -f "$CONFIG_FILE" ]; then
        if ! grep -q "send_mptcp\|accept_mptcp" "$CONFIG_FILE"; then
            sed -i '/^\[network\]/,/^$/s/use_udp = true/use_udp = true\nsend_mptcp = false\naccept_mptcp = false/' "$CONFIG_FILE"
            echo -e "${GREEN}已在现有配置文件中添加MPTCP支持${NC}"
        fi
    fi
}

manage_mptcp() {
    check_root
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}配置文件不存在: $CONFIG_FILE${NC}"
        return
    fi
    
    if ! grep -q "send_mptcp\|accept_mptcp" "$CONFIG_FILE"; then
        echo -e "${YELLOW}当前配置文件不支持MPTCP功能${NC}"
        return
    fi
    
    echo -e "${BLUE}当前MPTCP配置状态:${NC}"
    echo "------------------------------------"
    
    SEND_MPTCP=$(grep "send_mptcp" "$CONFIG_FILE" | grep -o "true\|false")
    ACCEPT_MPTCP=$(grep "accept_mptcp" "$CONFIG_FILE" | grep -o "true\|false")
    
    echo "send_mptcp: $SEND_MPTCP"
    echo "accept_mptcp: $ACCEPT_MPTCP"
    
    if check_mptcp_enabled; then
        echo -e "系统MPTCP状态: ${GREEN}已启用${NC}"
    else
        echo -e "系统MPTCP状态: ${RED}未启用${NC}"
    fi
    
    echo "------------------------------------"
    
    echo "MPTCP管理选项:"
    echo "1. 启用MPTCP (send_mptcp=true, accept_mptcp=true)"
    echo "2. 禁用MPTCP (send_mptcp=false, accept_mptcp=false)"
    echo "3. 仅启用发送 (send_mptcp=true, accept_mptcp=false)"
    echo "4. 仅启用接收 (send_mptcp=false, accept_mptcp=true)"
    echo "5. 返回主菜单"
    
    read -p "请选择 [1-5]: " mptcp_choice
    
    case $mptcp_choice in
        1)
            sed -i 's/send_mptcp = false/send_mptcp = true/' "$CONFIG_FILE"
            sed -i 's/accept_mptcp = false/accept_mptcp = true/' "$CONFIG_FILE"
            echo -e "${GREEN}已启用MPTCP功能${NC}"
            ;;
        2)
            sed -i 's/send_mptcp = true/send_mptcp = false/' "$CONFIG_FILE"
            sed -i 's/accept_mptcp = true/accept_mptcp = false/' "$CONFIG_FILE"
            echo -e "${YELLOW}已禁用MPTCP功能${NC}"
            ;;
        3)
            sed -i 's/send_mptcp = false/send_mptcp = true/' "$CONFIG_FILE"
            sed -i 's/accept_mptcp = true/accept_mptcp = false/' "$CONFIG_FILE"
            echo -e "${GREEN}已启用MPTCP发送功能${NC}"
            ;;
        4)
            sed -i 's/send_mptcp = true/send_mptcp = false/' "$CONFIG_FILE"
            sed -i 's/accept_mptcp = false/accept_mptcp = true/' "$CONFIG_FILE"
            echo -e "${GREEN}已启用MPTCP接收功能${NC}"
            ;;
        5)
            return
            ;;
        *)
            echo -e "${RED}无效的选择${NC}"
            return
            ;;
    esac
    
    read -p "是否重启realm服务以应用更改? (y/n): " restart_service
    if [[ "$restart_service" =~ ^[Yy]$ ]]; then
        if systemctl is-active --quiet realm; then
            systemctl restart realm
            echo -e "${GREEN}服务已重启${NC}"
        else
            systemctl start realm
            echo -e "${GREEN}服务已启动${NC}"
        fi
    fi
}

add_new_forwarding() {
    check_root
    read -p "请输入本地监听端口: " LOCAL_PORT
    read -p "请输入远程目标地址(IP或域名): " REMOTE_TARGET
    read -p "请输入远程目标端口: " REMOTE_PORT

    if [[ "$REMOTE_TARGET" =~ : ]]; then
        if [[ ! "$REMOTE_TARGET" =~ ^\[.*\]$ ]]; then
            REMOTE_TARGET="[$REMOTE_TARGET]"
        fi
    fi

    MPTCP_SUPPORTED=false
    if grep -q "send_mptcp\|accept_mptcp" "$CONFIG_FILE" 2>/dev/null; then
        MPTCP_SUPPORTED=true
    fi

    ENABLE_MPTCP=false
    if [ "$MPTCP_SUPPORTED" = "true" ]; then
        read -p "是否启用MPTCP支持? (y/n): " USE_MPTCP
        if [[ "$USE_MPTCP" =~ ^[Yy]$ ]]; then
            ENABLE_MPTCP=true
            sed -i 's/send_mptcp = false/send_mptcp = true/' "$CONFIG_FILE"
            sed -i 's/accept_mptcp = false/accept_mptcp = true/' "$CONFIG_FILE"
            echo -e "${GREEN}已启用全局MPTCP支持${NC}"
        fi
    fi

    read -p "是否配置加密隧道? (y/n): " USE_ENCRYPTION
    ENCRYPTION_CONFIG=""
    
    if [[ "$USE_ENCRYPTION" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}请选择加密隧道类型:${NC}"
        echo "1. TLS"
        echo "2. WebSocket (WS)"
        echo "3. WebSocket + TLS (WSS)"
        read -p "请选择 [1-3]: " ENCRYPTION_TYPE
        
        case $ENCRYPTION_TYPE in
            1) # TLS
                read -p "请输入 SNI 域名: " SNI_DOMAIN
                read -p "是否开启 insecure 选项? (y/n): " USE_INSECURE
                
                if [[ "$USE_INSECURE" =~ ^[Yy]$ ]]; then
                    ENCRYPTION_CONFIG="tls;sni=$SNI_DOMAIN;insecure"
                else
                    ENCRYPTION_CONFIG="tls;servername=$SNI_DOMAIN"
                fi
                ;;
            2) # WS
                read -p "请输入 Host 域名: " WS_HOST
                read -p "请输入 Path (默认为/wechat): " WS_PATH
                if [ -z "$WS_PATH" ]; then
                    WS_PATH="/wechat"
                fi
                ENCRYPTION_CONFIG="ws;host=$WS_HOST;path=$WS_PATH"
                ;;
            3) # WSS
                read -p "是否开启 insecure 选项? (y/n): " USE_INSECURE
                read -p "请输入 Host 域名: " WS_HOST
                read -p "请输入 Path (默认为/wechat): " WS_PATH
                read -p "请输入 SNI 域名: " SNI_DOMAIN
                
                if [ -z "$WS_PATH" ]; then
                    WS_PATH="/wechat"
                fi
                
                if [[ "$USE_INSECURE" =~ ^[Yy]$ ]]; then
                    ENCRYPTION_CONFIG="ws;host=$WS_HOST;path=$WS_PATH;tls;sni=$SNI_DOMAIN;insecure"
                else
                    ENCRYPTION_CONFIG="ws;host=$WS_HOST;path=$WS_PATH;tls;servername=$SNI_DOMAIN"
                fi
                ;;
            *)
                echo -e "${RED}无效的选择，将不使用加密隧道${NC}"
                ;;
        esac
    fi

    if [ -n "$ENCRYPTION_CONFIG" ]; then
        echo -e "\n[[endpoints]]\nlisten = \"0.0.0.0:${LOCAL_PORT}\"\nremote = \"${REMOTE_TARGET}:${REMOTE_PORT}\"\nremote_transport = \"${ENCRYPTION_CONFIG}\"" >> "$CONFIG_FILE"
        echo -e "${GREEN}已添加新的加密转发规则: 0.0.0.0:${LOCAL_PORT} -> ${REMOTE_TARGET}:${REMOTE_PORT} (加密类型: ${ENCRYPTION_CONFIG})${NC}"
    else
        echo -e "\n[[endpoints]]\nlisten = \"0.0.0.0:${LOCAL_PORT}\"\nremote = \"${REMOTE_TARGET}:${REMOTE_PORT}\"" >> "$CONFIG_FILE"
        echo -e "${GREEN}已添加新的转发规则: 0.0.0.0:${LOCAL_PORT} -> ${REMOTE_TARGET}:${REMOTE_PORT}${NC}"
    fi
    
    if [ "$ENABLE_MPTCP" = "true" ]; then
        echo -e "${GREEN}转发规则已启用MPTCP支持${NC}"
    fi
    
    if systemctl is-active --quiet realm; then
        echo "重启realm服务..."
        systemctl restart realm
        echo -e "${GREEN}服务已重启${NC}"
    else
        echo "realm服务未运行，正在启动..."
        systemctl start realm
        echo -e "${GREEN}服务已启动${NC}"
    fi
}

delete_forwarding() {
    check_root
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}配置文件不存在: $CONFIG_FILE${NC}"
        return
    fi
    
    echo -e "${BLUE}当前转发规则:${NC}"
    echo "------------------------------------"
    
    RULES=$(awk '
    BEGIN { count = 0; endpoint_start = 0; }
    /\[\[endpoints\]\]/ { 
      endpoint_start = NR;
      endpoints[count] = endpoint_start;
      count++;
    }
    /listen =/ { 
      gsub(/"/, "", $3);
      listen[count-1] = $3;
    }
    /remote =/ { 
      gsub(/"/, "", $3);
      remote[count-1] = $3;
    }
    /remote_transport =/ { 
      gsub(/"/, "", $3);
      transport[count-1] = $3;
    }
    END {
      for (i = 0; i < count; i++) {
        if (transport[i]) {
          print i " : " listen[i] " -> " remote[i] " (加密: " transport[i] ")";
        } else {
          print i " : " listen[i] " -> " remote[i];
        }
        print endpoints[i];
      }
    }' "$CONFIG_FILE")
    
    if [ -z "$RULES" ]; then
        echo "没有找到转发规则"
        return
    fi
    
    RULE_COUNT=$(echo "$RULES" | awk 'NR % 2 == 1 {count++} END {print count}')
    
    if [ "$RULE_COUNT" -eq 0 ]; then
        echo "没有找到转发规则"
        return
    fi
    
    DISPLAY_RULES=$(echo "$RULES" | awk 'NR % 2 == 1 {print}')
    RULE_LINES=$(echo "$RULES" | awk 'NR % 2 == 0 {print}')
    
    echo "$DISPLAY_RULES"
    echo "------------------------------------"
    
    read -p "请输入要删除的规则序号 [0-$((RULE_COUNT-1))]: " RULE_NUM
    
    if ! [[ "$RULE_NUM" =~ ^[0-9]+$ ]] || [ "$RULE_NUM" -ge "$RULE_COUNT" ]; then
        echo -e "${RED}无效的规则序号${NC}"
        return
    fi
    
    LINE_NUM=$(echo "$RULE_LINES" | sed -n "$((RULE_NUM+1))p")
    
    START_LINE=$LINE_NUM
    
    if [ "$RULE_NUM" -lt "$((RULE_COUNT-1))" ]; then
        NEXT_LINE=$(echo "$RULE_LINES" | sed -n "$((RULE_NUM+2))p")
        END_LINE=$((NEXT_LINE-1))
    else
        END_LINE=$(wc -l < "$CONFIG_FILE")
    fi
    
    TEMP_CONFIG=$(mktemp)
    
    if [ "$START_LINE" -gt 1 ]; then
        head -n $((START_LINE-1)) "$CONFIG_FILE" > "$TEMP_CONFIG"
    else
        > "$TEMP_CONFIG"
    fi
    
    if [ "$END_LINE" -lt "$(wc -l < "$CONFIG_FILE")" ]; then
        tail -n $(($(wc -l < "$CONFIG_FILE") - END_LINE)) "$CONFIG_FILE" >> "$TEMP_CONFIG"
    fi
    
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    
    mv "$TEMP_CONFIG" "$CONFIG_FILE"
    
    echo -e "${GREEN}已删除规则序号 $RULE_NUM${NC}"
    
    if systemctl is-active --quiet realm; then
        echo "重启realm服务..."
        systemctl restart realm
        echo -e "${GREEN}服务已重启${NC}"
    else
        echo "realm服务未运行，正在启动..."
        systemctl start realm
        echo -e "${GREEN}服务已启动${NC}"
    fi
}

uninstall_realm() {
    check_root
    echo -e "${YELLOW}正在卸载Realm...${NC}"
    
    if systemctl is-active --quiet realm; then
        echo "停止realm服务..."
        systemctl stop realm
    fi
    
    if systemctl is-enabled --quiet realm; then
        echo "禁用realm服务..."
        systemctl disable realm
    fi
    
    if [ -f "$SERVICE_FILE" ]; then
        echo "删除服务文件..."
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi
    
    if [ -f "$INSTALL_DIR/realm" ]; then
        echo "删除二进制文件..."
        rm -f "$INSTALL_DIR/realm"
    fi
    
    read -p "是否删除配置文件? (y/n): " REMOVE_CONFIG
    if [[ "$REMOVE_CONFIG" =~ ^[Yy]$ ]]; then
        echo "删除配置目录..."
        rm -rf "$CONFIG_DIR"
    else
        echo "保留配置文件，位置: $CONFIG_DIR"
    fi
    
    echo "删除realm-x命令..."
    
    TEMP_SCRIPT=$(mktemp)
    cat > "$TEMP_SCRIPT" << 'EOF'
sleep 1
rm -f "/usr/local/bin/realm-x"
rm -f "$0"
EOF
    
    chmod +x "$TEMP_SCRIPT"
    
    echo -e "${GREEN}Realm 已成功卸载${NC}"
    echo "realm-x命令将在退出后删除"
    
    nohup "$TEMP_SCRIPT" > /dev/null 2>&1 &
    
    exit 0
}

perform_installation() {
    check_root
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR" || exit 1

    echo "获取最新版本..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/zhboner/realm/releases/latest | grep "tag_name" | cut -d '"' -f 4)

    if [ -z "$LATEST_VERSION" ]; then
        echo -e "${YELLOW}无法获取最新版本，使用默认版本 v2.7.0${NC}"
        LATEST_VERSION="v2.7.0"
    fi

    echo -e "${GREEN}最新版本: $LATEST_VERSION${NC}"
    
    MPTCP_SUPPORTED=false
    if check_and_configure_mptcp "$LATEST_VERSION"; then
        MPTCP_SUPPORTED=true
    fi

    DOWNLOAD_URL="https://github.com/zhboner/realm/releases/download/${LATEST_VERSION}"

    get_arch() {
        ARCH=$(uname -m)
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        
        case "$ARCH" in
            x86_64)
                case "$OS" in
                    linux)
                        if [ -f "/etc/alpine-release" ]; then
                            echo "x86_64-unknown-linux-musl"
                        else
                            echo "x86_64-unknown-linux-gnu"
                        fi
                        ;;
                    darwin)
                        echo "x86_64-apple-darwin"
                        ;;
                    msys*|mingw*|cygwin*)
                        echo "x86_64-pc-windows-msvc"
                        ;;
                    *)
                        echo "unsupported"
                        ;;
                esac
                ;;
            aarch64|arm64)
                case "$OS" in
                    linux)
                        if [ -f "/etc/alpine-release" ]; then
                            echo "aarch64-unknown-linux-musl"
                        else
                            echo "aarch64-unknown-linux-gnu"
                        fi
                        ;;
                    darwin)
                        echo "aarch64-apple-darwin"
                        ;;
                    android)
                        echo "aarch64-linux-android"
                        ;;
                    *)
                        echo "unsupported"
                        ;;
                esac
                ;;
            armv7*)
                if [ -f "/etc/alpine-release" ]; then
                    echo "armv7-unknown-linux-musleabihf"
                else
                    echo "armv7-unknown-linux-gnueabihf"
                fi
                ;;
            arm*)
                if [ -f "/etc/alpine-release" ]; then
                    echo "arm-unknown-linux-musleabihf"
                else
                    echo "arm-unknown-linux-gnueabihf"
                fi
                ;;
            *)
                echo "unsupported"
                ;;
        esac
    }

    CURRENT_ARCH=$(get_arch)

    if [ "$CURRENT_ARCH" = "unsupported" ]; then
        echo -e "${RED}不支持的系统架构${NC}"
        exit 1
    fi

    echo "检测到系统架构: $CURRENT_ARCH"
    FILENAME="realm-${CURRENT_ARCH}.tar.gz"
    DOWNLOAD_LINK="${DOWNLOAD_URL}/${FILENAME}"

    echo "开始下载 $DOWNLOAD_LINK"
    if command -v curl &>/dev/null; then
        curl -L -o "$FILENAME" "$DOWNLOAD_LINK"
    elif command -v wget &>/dev/null; then
        wget -O "$FILENAME" "$DOWNLOAD_LINK"
    else
        echo -e "${RED}需要安装curl或wget${NC}"
        exit 1
    fi

    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败${NC}"
        exit 1
    fi

    echo "下载完成，开始解压"
    tar -xzf "$FILENAME"

    if [ -d "$INSTALL_DIR" ] && [ -w "$INSTALL_DIR" ]; then
        echo "将realm二进制文件安装到 $INSTALL_DIR"
        cp realm "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/realm"
        REALM_PATH="$INSTALL_DIR/realm"
    else
        echo -e "${YELLOW}目录 $INSTALL_DIR 不存在或没有写入权限，将文件保存在当前目录${NC}"
        chmod +x realm
        REALM_PATH="$PWD/realm"
        INSTALL_DIR="$PWD"
        CONFIG_DIR="$PWD/realm_config"
        SERVICE_FILE="$PWD/realm.service"
        CONFIG_FILE="$CONFIG_DIR/realm.toml"
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "配置文件不存在，将创建基本配置..."
        
        if [ -d "$CONFIG_DIR" ] || mkdir -p "$CONFIG_DIR"; then
            echo "创建配置文件 $CONFIG_FILE"
            create_config_with_mptcp "$MPTCP_SUPPORTED"
        else
            echo -e "${YELLOW}无法创建配置目录 $CONFIG_DIR${NC}"
            CONFIG_DIR="$PWD"
            CONFIG_FILE="$CONFIG_DIR/realm.toml"
            create_config_with_mptcp "$MPTCP_SUPPORTED"
        fi
        
        echo -e "${YELLOW}请在安装完成后使用 'realm-x -a' 命令添加转发规则${NC}"
    else
        echo "检测到已存在配置文件，保留现有配置"
        if [ "$MPTCP_SUPPORTED" = "true" ]; then
            update_config_with_mptcp
        fi
    fi

    if [ "$MPTCP_SUPPORTED" = "true" ]; then
        echo -e "${GREEN}此版本支持MPTCP功能，您可以使用 'realm-x --mptcp' 管理MPTCP设置${NC}"
    fi

    if [ -d "/etc/systemd/system" ] && [ -w "/etc/systemd/system" ]; then
        echo "创建systemd服务文件 $SERVICE_FILE"
        cat > "$SERVICE_FILE" << EOF
[Unit]
Description=realm
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=always
RestartSec=5s
DynamicUser=true
ExecStart=$REALM_PATH -c $CONFIG_FILE

[Install]
WantedBy=multi-user.target
EOF

        echo "启用并启动服务"
        systemctl daemon-reload
        systemctl enable realm
        systemctl start realm
        
        echo -e "${GREEN}realm服务已安装并启动${NC}"
        echo "配置文件位置: $CONFIG_FILE"
        echo "服务状态: $(systemctl status realm | grep Active)"
    else
        echo -e "${YELLOW}无法创建systemd服务文件，请手动配置启动项${NC}"
        cat > "$SERVICE_FILE" << EOF
[Unit]
Description=realm
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=always
RestartSec=5s
DynamicUser=true
ExecStart=$REALM_PATH -c $CONFIG_FILE

[Install]
WantedBy=multi-user.target
EOF
        echo "服务文件已保存到 $SERVICE_FILE"
    fi

    install_command

    echo "清理临时文件"
    rm -f "$FILENAME"
    cd - > /dev/null
    rm -rf "$TMP_DIR"

    echo -e "${GREEN}Realm 安装完成${NC}"
    echo "二进制文件位置: $REALM_PATH"
    echo "配置文件位置: $CONFIG_FILE"
    echo -e "${GREEN}您现在可以使用 'realm-x -a' 命令添加转发规则${NC}"
}

show_current_rules() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}配置文件不存在: $CONFIG_FILE${NC}"
        return
    fi

    if grep -q "send_mptcp\|accept_mptcp" "$CONFIG_FILE" 2>/dev/null; then
        echo -e "${BLUE}MPTCP配置状态:${NC}"
        SEND_MPTCP=$(grep "send_mptcp" "$CONFIG_FILE" | grep -o "true\|false")
        ACCEPT_MPTCP=$(grep "accept_mptcp" "$CONFIG_FILE" | grep -o "true\|false")
        echo "send_mptcp: $SEND_MPTCP, accept_mptcp: $ACCEPT_MPTCP"
        echo "------------------------------------"
    fi

    echo -e "${GREEN}当前转发规则:${NC}"
    echo "------------------------------------"
    
    RULES=$(awk '
    BEGIN { count = 0; }
    /\[\[endpoints\]\]/ { 
      count++;
    }
    /listen =/ { 
      gsub(/"/, "", $3);
      listen[count-1] = $3;
    }
    /remote =/ { 
      gsub(/"/, "", $3);
      remote[count-1] = $3;
    }
    /remote_transport =/ { 
      gsub(/"/, "", $3);
      transport[count-1] = $3;
    }
    END {
      if (count == 0) {
        print "没有找到转发规则，使用 \"realm-x -a\" 添加规则";
      } else {
        for (i = 0; i < count; i++) {
          if (transport[i]) {
            print i " : " listen[i] " -> " remote[i] " (加密: " transport[i] ")";
          } else {
            print i " : " listen[i] " -> " remote[i];
          }
        }
      }
    }' "$CONFIG_FILE")
    
    echo "$RULES"
    echo "------------------------------------"
}

edit_config() {
    check_root
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}配置文件不存在: $CONFIG_FILE${NC}"
        return
    fi
    
    if command -v nano &>/dev/null; then
        nano "$CONFIG_FILE"
    elif command -v vim &>/dev/null; then
        vim "$CONFIG_FILE"
    elif command -v vi &>/dev/null; then
        vi "$CONFIG_FILE"
    else
        echo -e "${YELLOW}未找到可用的文本编辑器(nano, vim, vi)${NC}"
        return
    fi
    
    echo "配置文件已编辑，是否重启服务? (y/n): "
    read restart
    if [[ "$restart" =~ ^[Yy]$ ]]; then
        if systemctl is-active --quiet realm; then
            systemctl restart realm
            echo -e "${GREEN}服务已重启${NC}"
        else
            systemctl start realm
            echo -e "${GREEN}服务已启动${NC}"
        fi
    fi
}

show_help() {
    echo -e "${BLUE}Realm 管理工具 (realm-x)${NC}"
    echo "使用方法: $SCRIPT_NAME [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help       显示此帮助信息"
    echo "  -i, --install    安装或更新Realm"
    echo "  -s, --status     查看Realm状态"
    echo "  -r, --restart    重启Realm服务"
    echo "  -l, --list       列出当前转发规则"
    echo "  -a, --add        添加新的转发规则"
    echo "  -d, --delete     删除转发规则"
    echo "  -e, --edit       编辑配置文件"
    echo "  -m, --mptcp      管理MPTCP设置"
    echo "  -u, --uninstall  卸载Realm"
    echo ""
    echo "不带参数运行将显示交互式菜单"
}

main_menu() {
    clear
    echo -e "${BLUE}====== Realm 管理脚本 ======${NC}"

    SHOW_MPTCP=false
    if [ -f "/proc/sys/net/mptcp/enabled" ]; then
        SHOW_MPTCP=true
    fi

    if [ "$SHOW_MPTCP" = true ]; then
        echo "1. 安装或更新 Realm"
        echo "2. 显示当前转发规则"
        echo "3. 添加新的转发规则"
        echo "4. 删除转发规则"
        echo "5. 编辑配置文件"
        echo "6. 管理MPTCP设置"
        echo "7. 重启 Realm 服务"
        echo "8. 查看 Realm 状态"
        echo "9. 卸载 Realm"
        echo "10. 退出"
        echo -e "${BLUE}===========================${NC}"
        read -p "请选择操作 [1-10]: " choice
        case $choice in
            1) perform_installation ;;
            2) show_current_rules ;;
            3) if check_installation; then add_new_forwarding; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            4) if check_installation; then delete_forwarding; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            5) if check_installation; then edit_config; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            6) if check_installation; then manage_mptcp; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            7) check_root; if systemctl list-unit-files | grep -q realm.service; then systemctl restart realm; echo -e "${GREEN}服务已重启${NC}"; else echo -e "${YELLOW}Realm 服务未安装${NC}"; fi ;;
            8) if systemctl list-unit-files | grep -q realm.service; then systemctl status realm; else echo -e "${YELLOW}Realm 服务未安装${NC}"; fi ;;
            9) if check_installation; then read -p "确定要卸载? (y/n): " confirm; if [[ "$confirm" =~ ^[Yy]$ ]]; then uninstall_realm; fi; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            10) echo "退出脚本"; exit 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
    else
        echo "1. 安装或更新 Realm"
        echo "2. 显示当前转发规则"
        echo "3. 添加新的转发规则"
        echo "4. 删除转发规则"
        echo "5. 编辑配置文件"
        echo "6. 重启 Realm 服务"
        echo "7. 查看 Realm 状态"
        echo "8. 卸载 Realm"
        echo "9. 退出"
        echo -e "${BLUE}===========================${NC}"
        read -p "请选择操作 [1-9]: " choice
        case $choice in
            1) perform_installation ;;
            2) show_current_rules ;;
            3) if check_installation; then add_new_forwarding; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            4) if check_installation; then delete_forwarding; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            5) if check_installation; then edit_config; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            6) check_root; if systemctl list-unit-files | grep -q realm.service; then systemctl restart realm; echo -e "${GREEN}服务已重启${NC}"; else echo -e "${YELLOW}Realm 服务未安装${NC}"; fi ;;
            7) if systemctl list-unit-files | grep -q realm.service; then systemctl status realm; else echo -e "${YELLOW}Realm 服务未安装${NC}"; fi ;;
            8) if check_installation; then read -p "确定要卸载? (y/n): " confirm; if [[ "$confirm" =~ ^[Yy]$ ]]; then uninstall_realm; fi; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            9) echo "退出脚本"; exit 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
    fi

    read -p "按任意键返回主菜单..." key
    main_menu
}

parse_args() {
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -i|--install)
            perform_installation
            exit 0
            ;;
        -s|--status)
            if systemctl list-unit-files | grep -q realm.service; then
                systemctl status realm
            else
                echo -e "${YELLOW}Realm 服务未安装${NC}"
            fi
            exit 0
            ;;
        -r|--restart)
            check_root
            if systemctl list-unit-files | grep -q realm.service; then
                systemctl restart realm
                echo -e "${GREEN}Realm 服务已重启${NC}"
            else
                echo -e "${YELLOW}Realm 服务未安装${NC}"
            fi
            exit 0
            ;;
        -l|--list)
            show_current_rules
            exit 0
            ;;
        -a|--add)
            if check_installation; then
                add_new_forwarding
            else
                echo -e "${YELLOW}Realm 尚未安装，请先安装${NC}"
            fi
            exit 0
            ;;
        -d|--delete)
            if check_installation; then
                delete_forwarding
            else
                echo -e "${YELLOW}Realm 尚未安装，请先安装${NC}"
            fi
            exit 0
            ;;
        -e|--edit)
            if check_installation; then
                edit_config
            else
                echo -e "${YELLOW}Realm 尚未安装，请先安装${NC}"
            fi
            exit 0
            ;;
        -m|--mptcp)
            if check_installation; then
                manage_mptcp
            else
                echo -e "${YELLOW}Realm 尚未安装，请先安装${NC}"
            fi
            exit 0
            ;;
        -u|--uninstall)
            if check_installation; then
                read -p "确定要卸载 Realm 吗? (y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    uninstall_realm
                else
                    echo "已取消卸载"
                fi
            else
                echo -e "${YELLOW}Realm 尚未安装${NC}"
            fi
            exit 0
            ;;
        "")
            main_menu
            ;;
        *)
            echo -e "${RED}未知选项: $1${NC}"
            show_help
            exit 1
            ;;
    esac
}

parse_args "$1"
REALMX_SCRIPT

    chmod +x "$SCRIPT_PATH"
    
    echo -e "${GREEN}realm-x命令已安装到系统${NC}"
}

show_current_rules() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}配置文件不存在: $CONFIG_FILE${NC}"
        return
    fi
    
    echo -e "${GREEN}当前转发规则:${NC}"
    echo "------------------------------------"
    
    RULES=$(awk '
    BEGIN { count = 0; }
    /\[\[endpoints\]\]/ { 
      count++;
    }
    /listen =/ { 
      gsub(/"/, "", $3);
      listen[count-1] = $3;
    }
    /remote =/ { 
      gsub(/"/, "", $3);
      remote[count-1] = $3;
    }
    /remote_transport =/ { 
      gsub(/"/, "", $3);
      transport[count-1] = $3;
    }
    END {
      if (count == 0) {
        print "没有找到转发规则，使用 \"realm-x -a\" 添加规则";
      } else {
        for (i = 0; i < count; i++) {
          if (transport[i]) {
            print i " : " listen[i] " -> " remote[i] " (加密: " transport[i] ")";
          } else {
            print i " : " listen[i] " -> " remote[i];
          }
        }
      }
    }' "$CONFIG_FILE")
    
    echo "$RULES"
    echo "------------------------------------"
}

edit_config() {
    check_root
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}配置文件不存在: $CONFIG_FILE${NC}"
        return
    fi
    
    if command -v nano &>/dev/null; then
        nano "$CONFIG_FILE"
    elif command -v vim &>/dev/null; then
        vim "$CONFIG_FILE"
    elif command -v vi &>/dev/null; then
        vi "$CONFIG_FILE"
    else
        echo -e "${YELLOW}未找到可用的文本编辑器(nano, vim, vi)${NC}"
        return
    fi
    
    echo "配置文件已编辑，是否重启服务? (y/n): "
    read restart
    if [[ "$restart" =~ ^[Yy]$ ]]; then
        if systemctl is-active --quiet realm; then
            systemctl restart realm
            echo -e "${GREEN}服务已重启${NC}"
        else
            systemctl start realm
            echo -e "${GREEN}服务已启动${NC}"
        fi
    fi
}

show_help() {
    echo -e "${BLUE}Realm 管理工具 (realm-x)${NC}"
    echo "使用方法: $SCRIPT_NAME [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help       显示此帮助信息"
    echo "  -i, --install    安装或更新Realm"
    echo "  -s, --status     查看Realm状态"
    echo "  -r, --restart    重启Realm服务"
    echo "  -l, --list       列出当前转发规则"
    echo "  -a, --add        添加新的转发规则"
    echo "  -d, --delete     删除转发规则"
    echo "  -e, --edit       编辑配置文件"
    echo "  -m, --mptcp      管理MPTCP设置"
    echo "  -u, --uninstall  卸载Realm"
    echo ""
    echo "不带参数运行将显示交互式菜单"
}

main_menu() {
    clear
    echo -e "${BLUE}====== Realm 管理脚本 ======${NC}"

    SHOW_MPTCP=false
    if [ -f "/proc/sys/net/mptcp/enabled" ]; then
        SHOW_MPTCP=true
    fi

    if [ "$SHOW_MPTCP" = true ]; then
        echo "1. 安装或更新 Realm"
        echo "2. 显示当前转发规则"
        echo "3. 添加新的转发规则"
        echo "4. 删除转发规则"
        echo "5. 编辑配置文件"
        echo "6. 管理MPTCP设置"
        echo "7. 重启 Realm 服务"
        echo "8. 查看 Realm 状态"
        echo "9. 卸载 Realm"
        echo "10. 退出"
        echo -e "${BLUE}===========================${NC}"
        read -p "请选择操作 [1-10]: " choice
        case $choice in
            1) perform_installation ;;
            2) show_current_rules ;;
            3) if check_installation; then add_new_forwarding; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            4) if check_installation; then delete_forwarding; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            5) if check_installation; then edit_config; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            6) if check_installation; then manage_mptcp; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            7) check_root; if systemctl list-unit-files | grep -q realm.service; then systemctl restart realm; echo -e "${GREEN}服务已重启${NC}"; else echo -e "${YELLOW}Realm 服务未安装${NC}"; fi ;;
            8) if systemctl list-unit-files | grep -q realm.service; then systemctl status realm; else echo -e "${YELLOW}Realm 服务未安装${NC}"; fi ;;
            9) if check_installation; then read -p "确定要卸载? (y/n): " confirm; if [[ "$confirm" =~ ^[Yy]$ ]]; then uninstall_realm; fi; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            10) echo "退出脚本"; exit 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
    else
        echo "1. 安装或更新 Realm"
        echo "2. 显示当前转发规则"
        echo "3. 添加新的转发规则"
        echo "4. 删除转发规则"
        echo "5. 编辑配置文件"
        echo "6. 重启 Realm 服务"
        echo "7. 查看 Realm 状态"
        echo "8. 卸载 Realm"
        echo "9. 退出"
        echo -e "${BLUE}===========================${NC}"
        read -p "请选择操作 [1-9]: " choice
        case $choice in
            1) perform_installation ;;
            2) show_current_rules ;;
            3) if check_installation; then add_new_forwarding; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            4) if check_installation; then delete_forwarding; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            5) if check_installation; then edit_config; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            6) check_root; if systemctl list-unit-files | grep -q realm.service; then systemctl restart realm; echo -e "${GREEN}服务已重启${NC}"; else echo -e "${YELLOW}Realm 服务未安装${NC}"; fi ;;
            7) if systemctl list-unit-files | grep -q realm.service; then systemctl status realm; else echo -e "${YELLOW}Realm 服务未安装${NC}"; fi ;;
            8) if check_installation; then read -p "确定要卸载? (y/n): " confirm; if [[ "$confirm" =~ ^[Yy]$ ]]; then uninstall_realm; fi; else echo -e "${YELLOW}Realm 尚未安装${NC}"; fi ;;
            9) echo "退出脚本"; exit 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
    fi

    read -p "按任意键返回主菜单..." key
    main_menu
}

parse_args() {
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -i|--install)
            perform_installation
            exit 0
            ;;
        -s|--status)
            if systemctl list-unit-files | grep -q realm.service; then
                systemctl status realm
            else
                echo -e "${YELLOW}Realm 服务未安装${NC}"
            fi
            exit 0
            ;;
        -r|--restart)
            check_root
            if systemctl list-unit-files | grep -q realm.service; then
                systemctl restart realm
                echo -e "${GREEN}Realm 服务已重启${NC}"
            else
                echo -e "${YELLOW}Realm 服务未安装${NC}"
            fi
            exit 0
            ;;
        -l|--list)
            show_current_rules
            exit 0
            ;;
        -a|--add)
            if check_installation; then
                add_new_forwarding
            else
                echo -e "${YELLOW}Realm 尚未安装，请先安装${NC}"
            fi
            exit 0
            ;;
        -d|--delete)
            if check_installation; then
                delete_forwarding
            else
                echo -e "${YELLOW}Realm 尚未安装，请先安装${NC}"
            fi
            exit 0
            ;;
        -e|--edit)
            if check_installation; then
                edit_config
            else
                echo -e "${YELLOW}Realm 尚未安装，请先安装${NC}"
            fi
            exit 0
            ;;
        -m|--mptcp)
            if check_installation; then
                manage_mptcp
            else
                echo -e "${YELLOW}Realm 尚未安装，请先安装${NC}"
            fi
            exit 0
            ;;
        -u|--uninstall)
            if check_installation; then
                read -p "确定要卸载 Realm 吗? (y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    uninstall_realm
                else
                    echo "已取消卸载"
                fi
            else
                echo -e "${YELLOW}Realm 尚未安装${NC}"
            fi
            exit 0
            ;;
        "")
            main_menu
            ;;
        *)
            echo -e "${RED}未知选项: $1${NC}"
            show_help
            exit 1
            ;;
    esac
}

if [[ "$0" != "$SCRIPT_PATH" && "$1" != "--self-install" ]]; then
    echo "首次运行，安装realm-x命令..."
    
    check_root
    
    install_command
    
    echo -e "${GREEN}您现在可以运行 'realm-x' 命令来管理Realm${NC}"
    echo "正在启动主菜单..."
    
    "$SCRIPT_PATH"
else
    parse_args "$1"
fi