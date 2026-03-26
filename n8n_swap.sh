#!/bin/bash

# Hiển thị banner
echo "======================================================================"
echo "     Script cài đặt N8N v2.0 + SSL tự động + FFmpeg"
echo "======================================================================"

# Kiểm tra xem script có được chạy với quyền root không
if [[ $EUID -ne 0 ]]; then
   echo "Script này cần được chạy với quyền root"
   exit 1
fi

# ====================================================================
# Tạo Swap 2GB (nếu chưa có)
# ====================================================================
echo "Kiểm tra swap hiện tại..."
CURRENT_SWAP=$(swapon --show | wc -l)
if [ "$CURRENT_SWAP" -le 1 ]; then
    echo "Chưa có swap. Tiến hành tạo swap 2GB..."
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    # Tự động mount khi reboot
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    # Giảm swappiness để ưu tiên dùng RAM trước
    if ! grep -q 'vm.swappiness' /etc/sysctl.conf; then
        echo 'vm.swappiness=10' >> /etc/sysctl.conf
    fi
    sysctl -p

    echo "✓ Đã tạo swap 2GB thành công!"
    free -h
else
    echo "✓ Swap đã tồn tại, bỏ qua bước này."
    swapon --show
fi

# Hàm hiển thị trợ giúp
show_help() {
    echo "Cách sử dụng: $0 [tùy chọn]"
    echo "Tùy chọn:"
    echo "  -h, --help      Hiển thị trợ giúp này"
    echo "  -d, --dir DIR   Chỉ định thư mục cài đặt n8n (mặc định: /home/n8n)"
    echo "  -s, --skip-docker Bỏ qua cài đặt Docker (nếu đã có)"
    exit 0
}

# Xử lý tham số dòng lệnh
N8N_DIR="/home/n8n"
SKIP_DOCKER=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -d|--dir)
            N8N_DIR="$2"
            shift 2
            ;;
        -s|--skip-docker)
            SKIP_DOCKER=true
            shift
            ;;
        *)
            echo "Tùy chọn không hợp lệ: $1"
            show_help
            ;;
    esac
done

# Hàm kiểm tra domain
check_domain() {
    local domain=$1
    local server_ip=$(curl -s https://api.ipify.org)
    local domain_ip=$(dig +short $domain)

    if [ "$domain_ip" = "$server_ip" ]; then
        return 0
    else
        return 1
    fi
}

# Hàm kiểm tra các lệnh cần thiết
check_commands() {
    if ! command -v dig &> /dev/null; then
        echo "Cài đặt dnsutils (để sử dụng lệnh dig)..."
        apt-get update
        apt-get install -y dnsutils
    fi
    if ! command -v curl &> /dev/null; then
        echo "Cài đặt curl..."
        apt-get update
        apt-get install -y curl
    fi
}

# Hàm cài đặt Docker
install_docker() {
    if $SKIP_DOCKER; then
        echo "Bỏ qua cài đặt Docker theo yêu cầu..."
        return
    fi

    echo "Cài đặt Docker và Docker Compose..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl software-properties-common

    # Thêm khóa Docker GPG (cách mới, không dùng apt-key deprecated)
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Thêm repository Docker
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Cài đặt Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io

    # Cài đặt Docker Compose
    if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
        echo "Cài đặt Docker Compose..."
        apt-get install -y docker-compose
    elif command -v docker &> /dev/null && ! docker compose version &> /dev/null; then
        echo "Cài đặt Docker Compose plugin..."
        apt-get install -y docker-compose-plugin
    fi

    # Kiểm tra Docker
    if ! command -v docker &> /dev/null; then
        echo "Lỗi: Docker chưa được cài đặt đúng cách."
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null && ! (command -v docker &> /dev/null && docker compose version &> /dev/null); then
        echo "Lỗi: Docker Compose chưa được cài đặt đúng cách."
        exit 1
    fi

    echo "Docker và Docker Compose đã được cài đặt thành công."
}

# Xác định docker compose command
get_docker_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo ""
    fi
}

# Cài đặt các gói cần thiết
echo "Đang cài đặt các công cụ cần thiết..."
apt-get update
apt-get install -y dnsutils curl cron

# Đảm bảo cron service đang chạy
systemctl enable cron
systemctl start cron

# Kiểm tra các lệnh cần thiết
check_commands

# Nhận input domain từ người dùng
read -p "Nhập tên miền hoặc tên miền phụ của bạn: " DOMAIN

# Kiểm tra domain
echo "Kiểm tra domain $DOMAIN..."
if check_domain "$DOMAIN"; then
    echo "Domain $DOMAIN đã được trỏ đúng đến server này. Tiếp tục cài đặt"
else
    echo "Domain $DOMAIN chưa được trỏ đến server này."
    echo "Vui lòng cập nhật bản ghi DNS để trỏ $DOMAIN đến IP $(curl -s https://api.ipify.org)"
    echo "Sau khi cập nhật DNS, hãy chạy lại script này"
    exit 1
fi

# Cài đặt Docker và Docker Compose
install_docker

# Tạo thư mục cho n8n
echo "Tạo cấu trúc thư mục cho n8n tại $N8N_DIR..."
mkdir -p "$N8N_DIR"
mkdir -p "$N8N_DIR/files"
mkdir -p "$N8N_DIR/files/temp"
mkdir -p "$N8N_DIR/my-files"

# ====================================================================
# Tạo Dockerfile
# ====================================================================
echo "Tạo Dockerfile tối ưu (multi-stage build)..."
cat << 'EOF' > $N8N_DIR/Dockerfile
# ==============================
# Stage 1: Lấy FFmpeg static binary
# ==============================
FROM mwader/static-ffmpeg:7.1 AS ffmpeg_source

# ==============================
# Stage 2: Build n8n custom
# ==============================
FROM n8nio/n8n:latest

USER root

# ==============================
# 1. Copy FFmpeg + FFprobe từ stage 1
# ==============================
COPY --from=ffmpeg_source /ffmpeg /usr/local/bin/ffmpeg
COPY --from=ffmpeg_source /ffprobe /usr/local/bin/ffprobe
RUN chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe

# ==============================
# 2. Tạo thư mục cho file access
# ==============================
RUN mkdir -p /files/temp /home/my-files && \
    chown -R 1000:1000 /files /home/my-files /home/node

# ==============================
# 3. Verify installations
# ==============================
RUN echo "=== Verifying ===" && \
    ffmpeg -version | head -n 1 && \
    ffprobe -version | head -n 1 && \
    echo "=== All OK ==="

USER node
EOF

# ====================================================================
# Tạo file docker-compose.yml
# ====================================================================
echo "Tạo file docker-compose.yml tối ưu..."
cat << EOF > $N8N_DIR/docker-compose.yml
services:
  n8n:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      # === Cấu hình cơ bản ===
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh

      # === Binary Data ===
      - N8N_DEFAULT_BINARY_DATA_MODE=filesystem
      - N8N_BINARY_DATA_TTL=168

      # === File Access & Command Execution ===
      - N8N_RESTRICT_FILE_ACCESS_TO=/home/node;/home/my-files;/files;/tmp
      - NODES_EXCLUDE=[]
      - NODE_FUNCTION_ALLOW_BUILTIN=child_process,path,fs,util
      - NODE_FUNCTION_ALLOW_EXTERNAL=*

      # === Execution tuning ===
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=168
      - EXECUTIONS_DATA_PRUNE_MAX_COUNT=5000
      - N8N_EXECUTIONS_DATA_MAX_SIZE=304857600

      # === Security ===
      - N8N_DIAGNOSTICS_ENABLED=false
      - N8N_HIRING_BANNER_ENABLED=false

      # === Puppeteer / Chromium ===
      - PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
      - PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

      # === MCP / Community ===
      - N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true

    volumes:
      - ${N8N_DIR}:/home/node/.n8n
      - ${N8N_DIR}/files:/files
      - ${N8N_DIR}/my-files:/home/my-files
    user: "1000:1000"
    networks:
      - n8n_network
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  caddy:
    image: caddy:2
    container_name: caddy
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ${N8N_DIR}/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - n8n_network
    depends_on:
      n8n:
        condition: service_healthy

volumes:
  caddy_data:
    driver: local
  caddy_config:
    driver: local

networks:
  n8n_network:
    name: n8n_network
    driver: bridge
EOF

# ====================================================================
# Tạo file Caddyfile
# ====================================================================
echo "Tạo file Caddyfile..."
cat << EOF > $N8N_DIR/Caddyfile
${DOMAIN} {
    reverse_proxy n8n:5678
}
EOF

# ====================================================================
# Đặt quyền cho thư mục n8n
# ====================================================================
echo "Đặt quyền cho thư mục n8n..."
chown -R 1000:1000 "$N8N_DIR"
chmod -R 755 "$N8N_DIR"

# ====================================================================
# Khởi động các container
# ====================================================================
echo "Khởi động các container..."
echo "Lưu ý: Quá trình build image có thể mất vài phút (tải FFmpeg static binary)..."
cd $N8N_DIR

DOCKER_COMPOSE_CMD=$(get_docker_compose_cmd)
if [ -z "$DOCKER_COMPOSE_CMD" ]; then
    echo "Lỗi: Không tìm thấy lệnh docker-compose hoặc docker compose."
    exit 1
fi

$DOCKER_COMPOSE_CMD build --no-cache
$DOCKER_COMPOSE_CMD up -d

# Đợi container khởi động
echo "Đợi các container khởi động..."
echo "Đang chờ n8n healthy (có thể mất 30-60 giây)..."
WAIT_COUNT=0
MAX_WAIT=60
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if docker inspect --format='{{.State.Health.Status}}' n8n 2>/dev/null | grep -q "healthy"; then
        echo "✓ Container n8n đã healthy!"
        break
    fi
    sleep 5
    WAIT_COUNT=$((WAIT_COUNT + 5))
    echo "  Đang chờ... (${WAIT_COUNT}s/${MAX_WAIT}s)"
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    echo "⚠ n8n chưa healthy sau ${MAX_WAIT}s. Kiểm tra logs:"
    echo "  $DOCKER_COMPOSE_CMD logs n8n"
fi

# Kiểm tra containers
echo ""
echo "Kiểm tra trạng thái containers..."
if docker ps | grep -q "n8n"; then
    echo "✓ Container n8n đang chạy."
else
    echo "✗ Container n8n chưa chạy. Kiểm tra: $DOCKER_COMPOSE_CMD logs n8n"
fi

if docker ps | grep -q "caddy"; then
    echo "✓ Container caddy đang chạy."
else
    echo "✗ Container caddy chưa chạy. Kiểm tra: $DOCKER_COMPOSE_CMD logs caddy"
fi

# Kiểm tra tools trong container n8n
echo ""
echo "Kiểm tra tools trong container n8n..."
N8N_CONTAINER=$(docker ps -q --filter "name=n8n" 2>/dev/null)
if [ -n "$N8N_CONTAINER" ]; then
    echo "--- FFmpeg ---"
    docker exec $N8N_CONTAINER ffmpeg -version 2>/dev/null | head -n 1 || echo "✗ FFmpeg chưa sẵn sàng"
    echo "--- Bash ---"
    docker exec $N8N_CONTAINER bash --version 2>/dev/null | head -n 1 || echo "✗ Bash chưa sẵn sàng"
else
    echo "Container n8n chưa sẵn sàng để kiểm tra tools."
    echo "Kiểm tra thủ công: docker exec n8n ffmpeg -version"
fi

# ====================================================================
# Tạo script cập nhật tự động
# ====================================================================
echo ""
echo "Tạo script cập nhật tự động..."
cat << 'UPDATEEOF' > $N8N_DIR/update-n8n.sh
#!/bin/bash

# Đường dẫn đến thư mục n8n
N8N_DIR="PLACEHOLDER_N8N_DIR"

# Hàm ghi log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $N8N_DIR/update.log
}

# Xác định docker compose command
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    log "Không tìm thấy lệnh docker-compose hoặc docker compose."
    exit 1
fi

log "Bắt đầu kiểm tra cập nhật..."

# Lấy image ID hiện tại của n8nio/n8n
OLD_BASE_IMAGE_ID=$(docker images -q n8nio/n8n:latest)

# Pull image gốc mới nhất
log "Kéo image n8nio/n8n:latest mới nhất..."
docker pull n8nio/n8n:latest

# Lấy image ID mới
NEW_BASE_IMAGE_ID=$(docker images -q n8nio/n8n:latest)

# So sánh image cũ và mới
if [ "$NEW_BASE_IMAGE_ID" != "$OLD_BASE_IMAGE_ID" ]; then
    log "Phát hiện image mới (${NEW_BASE_IMAGE_ID}), tiến hành cập nhật..."

    # Sao lưu dữ liệu n8n
    BACKUP_DATE=$(date '+%Y%m%d_%H%M%S')
    BACKUP_FILE="$N8N_DIR/backup_${BACKUP_DATE}.zip"
    log "Tạo bản sao lưu tại $BACKUP_FILE"
    zip -r "$BACKUP_FILE" "$N8N_DIR" \
        -x "$N8N_DIR/update-n8n.sh" \
        -x "$N8N_DIR/backup_*" \
        -x "$N8N_DIR/files/temp/*" \
        -x "$N8N_DIR/Dockerfile" \
        -x "$N8N_DIR/docker-compose.yml"

    # Xóa backup cũ hơn 7 ngày
    find "$N8N_DIR" -name "backup_*.zip" -mtime +7 -delete
    log "Đã xóa các backup cũ hơn 7 ngày"

    # Build lại image
    cd "$N8N_DIR"
    log "Đang build lại image..."
    $DOCKER_COMPOSE build --no-cache

    # Khởi động lại container
    log "Khởi động lại container..."
    $DOCKER_COMPOSE down
    $DOCKER_COMPOSE up -d

    # Chờ healthy
    WAIT_COUNT=0
    MAX_WAIT=60
    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        if docker inspect --format='{{.State.Health.Status}}' n8n 2>/dev/null | grep -q "healthy"; then
            log "Container n8n đã healthy sau cập nhật!"
            break
        fi
        sleep 5
        WAIT_COUNT=$((WAIT_COUNT + 5))
    done

    if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
        log "CẢNH BÁO: n8n chưa healthy sau ${MAX_WAIT}s"
    fi

    # Dọn dẹp image cũ không dùng
    docker image prune -f
    log "Cập nhật hoàn tất, image mới: ${NEW_BASE_IMAGE_ID}"
else
    log "Không có cập nhật mới cho n8n"
fi
UPDATEEOF

# Thay thế placeholder bằng đường dẫn thực tế
sed -i "s|PLACEHOLDER_N8N_DIR|$N8N_DIR|g" $N8N_DIR/update-n8n.sh

# Đặt quyền thực thi cho script cập nhật
chmod +x $N8N_DIR/update-n8n.sh

# ====================================================================
# Tạo script backup thủ công
# ====================================================================
echo "Tạo script backup thủ công..."
cat << 'BACKUPEOF' > $N8N_DIR/backup-n8n.sh
#!/bin/bash

N8N_DIR="PLACEHOLDER_N8N_DIR"
BACKUP_DATE=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="$N8N_DIR/backup_${BACKUP_DATE}.zip"

echo "Đang tạo backup..."
zip -r "$BACKUP_FILE" "$N8N_DIR" \
    -x "$N8N_DIR/update-n8n.sh" \
    -x "$N8N_DIR/backup-n8n.sh" \
    -x "$N8N_DIR/backup_*" \
    -x "$N8N_DIR/files/temp/*" \
    -x "$N8N_DIR/Dockerfile" \
    -x "$N8N_DIR/docker-compose.yml" \
    -x "$N8N_DIR/update.log"

echo "✓ Backup hoàn tất: $BACKUP_FILE"
echo "  Kích thước: $(du -h "$BACKUP_FILE" | cut -f1)"
BACKUPEOF

sed -i "s|PLACEHOLDER_N8N_DIR|$N8N_DIR|g" $N8N_DIR/backup-n8n.sh
chmod +x $N8N_DIR/backup-n8n.sh

# ====================================================================
# Tạo script restart nhanh
# ====================================================================
echo "Tạo script restart nhanh..."
cat << 'RESTARTEOF' > $N8N_DIR/restart-n8n.sh
#!/bin/bash

N8N_DIR="PLACEHOLDER_N8N_DIR"
cd "$N8N_DIR"

if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

echo "Đang restart n8n..."
$DOCKER_COMPOSE restart n8n

echo "Đợi n8n healthy..."
WAIT_COUNT=0
while [ $WAIT_COUNT -lt 60 ]; do
    if docker inspect --format='{{.State.Health.Status}}' n8n 2>/dev/null | grep -q "healthy"; then
        echo "✓ n8n đã healthy!"
        exit 0
    fi
    sleep 5
    WAIT_COUNT=$((WAIT_COUNT + 5))
    echo "  Đang chờ... (${WAIT_COUNT}s)"
done

echo "⚠ n8n chưa healthy. Kiểm tra: $DOCKER_COMPOSE logs n8n"
RESTARTEOF

sed -i "s|PLACEHOLDER_N8N_DIR|$N8N_DIR|g" $N8N_DIR/restart-n8n.sh
chmod +x $N8N_DIR/restart-n8n.sh

# ====================================================================
# Tạo cron job cập nhật tự động mỗi 12 giờ
# ====================================================================
echo "Tạo cron job cập nhật tự động mỗi 12 giờ..."
CRON_JOB="0 */12 * * * $N8N_DIR/update-n8n.sh"
(crontab -l 2>/dev/null | grep -v "update-n8n.sh"; echo "$CRON_JOB") | crontab -

# ====================================================================
# Hoàn tất
# ====================================================================
echo ""
echo "======================================================================"
echo "  ✓ N8N đã được cài đặt và cấu hình thành công!                     "
echo "======================================================================"
echo ""
echo "  🌐 Truy cập: https://${DOMAIN}"
echo "  📁 Thư mục dữ liệu: $N8N_DIR"
echo "  📁 Thư mục files: $N8N_DIR/files"
echo "  📁 Thư mục my-files: $N8N_DIR/my-files"
echo ""
echo "  📦 Tools đã cài: FFmpeg, FFprobe"
echo ""
echo "  🔧 Scripts tiện ích:"
echo "    - Cập nhật:  $N8N_DIR/update-n8n.sh"
echo "    - Backup:    $N8N_DIR/backup-n8n.sh"
echo "    - Restart:   $N8N_DIR/restart-n8n.sh"
echo ""
echo "  ⏰ Tự động cập nhật: mỗi 12 giờ"
echo "  📋 Log cập nhật: $N8N_DIR/update.log"
echo ""
echo "  📝 Lệnh hữu ích:"
echo "    - Xem logs:    cd $N8N_DIR && $DOCKER_COMPOSE_CMD logs -f"
echo "    - Restart:     $N8N_DIR/restart-n8n.sh"
echo "    - Backup:      $N8N_DIR/backup-n8n.sh"
echo "    - Cập nhật:    $N8N_DIR/update-n8n.sh"
echo ""
echo "  ⚠️  SSL có thể mất vài phút để cấu hình hoàn tất."
echo "======================================================================"
