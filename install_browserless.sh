#!/bin/bash

# ====================================================================
# Script cài đặt Browserless Chrome (Puppeteer Server) độc lập
# Dùng để kết nối từ n8n hoặc bất kỳ app nào cần Puppeteer
# ====================================================================

echo "======================================================================"
echo "  Cài đặt Browserless Chrome (Puppeteer Server)                       "
echo "======================================================================"

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   echo "Script này cần được chạy với quyền root"
   exit 1
fi

# Kiểm tra Docker
if ! command -v docker &> /dev/null; then
    echo "Lỗi: Docker chưa được cài đặt. Hãy cài Docker trước."
    exit 1
fi

# ====================================================================
# Cấu hình
# ====================================================================
BROWSERLESS_DIR="/home/browserless"
BROWSERLESS_PORT=3000
MAX_CONCURRENT=5      # Số phiên trình duyệt đồng thời tối đa
MAX_QUEUED=10          # Số request chờ tối đa
TIMEOUT=120000         # Timeout mỗi phiên (ms) = 2 phút
MEMORY_LIMIT="1g"      # Giới hạn RAM

# ====================================================================
# Tạo thư mục
# ====================================================================
echo "Tạo thư mục $BROWSERLESS_DIR..."
mkdir -p "$BROWSERLESS_DIR"

# ====================================================================
# Tạo docker-compose.yml
# ====================================================================
echo "Tạo docker-compose.yml..."
cat << EOF > $BROWSERLESS_DIR/docker-compose.yml
services:
  browserless:
    image: ghcr.io/browserless/chromium:latest
    container_name: browserless
    restart: always
    ports:
      - "${BROWSERLESS_PORT}:3000"
    environment:
      # Số phiên trình duyệt đồng thời
      - CONCURRENT=${MAX_CONCURRENT}
      # Số request chờ trong hàng đợi
      - QUEUED=${MAX_QUEUED}
      # Timeout mỗi phiên (ms)
      - TIMEOUT=${TIMEOUT}
      # Bật health check endpoint
      - HEALTH=true
    deploy:
      resources:
        limits:
          memory: ${MEMORY_LIMIT}
    # Nếu n8n chạy trên cùng server, kết nối qua Docker network
    networks:
      - browserless_net

networks:
  browserless_net:
    name: browserless_net
    driver: bridge
EOF

# ====================================================================
# Khởi động container
# ====================================================================
echo "Khởi động Browserless Chrome..."
cd "$BROWSERLESS_DIR"
docker compose up -d

# Đợi khởi động
echo "Đợi container khởi động..."
sleep 5

# Kiểm tra
if docker ps | grep -q "browserless"; then
    echo "✓ Browserless Chrome đang chạy!"
else
    echo "✗ Lỗi khởi động. Kiểm tra: docker compose logs browserless"
    exit 1
fi

# Lấy IP server
SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "YOUR_SERVER_IP")

# ====================================================================
# Kết nối n8n container vào cùng network (nếu n8n đã chạy)
# ====================================================================
echo ""
echo "Kết nối n8n vào Browserless network..."
if docker ps | grep -q "n8n"; then
    docker network connect browserless_net n8n 2>/dev/null && \
        echo "✓ Đã kết nối container n8n vào browserless_net" || \
        echo "⚠ Container n8n đã ở trong network này rồi"
else
    echo "⚠ Container n8n chưa chạy. Kết nối sau bằng lệnh:"
    echo "  docker network connect browserless_net n8n"
fi

# ====================================================================
# Hoàn tất
# ====================================================================
echo ""
echo "======================================================================"
echo "  ✓ Browserless Chrome đã cài đặt thành công!                        "
echo "======================================================================"
echo ""
echo "  📍 Thư mục: $BROWSERLESS_DIR"
echo "  🌐 Port: $BROWSERLESS_PORT"
echo ""
echo "  ================================================"
echo "  CÁCH KẾT NỐI TỪ N8N:"
echo "  ================================================"
echo ""
echo "  1️⃣  Nếu n8n chạy cùng server (Docker):"
echo "     WebSocket URL: ws://browserless:3000"
echo ""
echo "     Chạy lệnh để kết nối network:"
echo "     docker network connect browserless_net n8n"
echo ""
echo "  2️⃣  Nếu n8n ở server khác:"
echo "     WebSocket URL: ws://${SERVER_IP}:${BROWSERLESS_PORT}"
echo ""
echo "  ================================================"
echo "  CÁCH DÙNG TRONG N8N:"
echo "  ================================================"
echo ""
echo "  📌 Cách 1: Node 'Code' (Puppeteer)"
echo "     const puppeteer = require('puppeteer-core');"
echo "     const browser = await puppeteer.connect({"
echo "       browserWSEndpoint: 'ws://browserless:3000',"
echo "     });"
echo "     const page = await browser.newPage();"
echo "     await page.goto('https://example.com');"
echo "     const screenshot = await page.screenshot();"
echo "     await browser.close();"
echo ""
echo "  📌 Cách 2: Node 'HTTP Request' (REST API)"
echo "     - Chụp ảnh trang web:"
echo "       POST http://browserless:3000/screenshot"
echo "       Body: {\"url\": \"https://example.com\"}"
echo ""
echo "     - Tạo PDF:"
echo "       POST http://browserless:3000/pdf"
echo "       Body: {\"url\": \"https://example.com\"}"
echo ""
echo "     - Lấy nội dung HTML:"
echo "       POST http://browserless:3000/content"
echo "       Body: {\"url\": \"https://example.com\"}"
echo ""
echo "     - Scrape dữ liệu:"
echo "       POST http://browserless:3000/scrape"
echo "       Body: {\"url\": \"https://example.com\","
echo "              \"elements\": [{\"selector\": \"h1\"}]}"
echo ""
echo "  📌 Cách 3: Mở trình duyệt debug (từ máy tính)"
echo "     http://${SERVER_IP}:${BROWSERLESS_PORT}/"
echo ""
echo "  ================================================"
echo "  LỆNH QUẢN LÝ:"
echo "  ================================================"
echo ""
echo "  Xem logs:     cd $BROWSERLESS_DIR && docker compose logs -f"
echo "  Restart:      cd $BROWSERLESS_DIR && docker compose restart"
echo "  Dừng:         cd $BROWSERLESS_DIR && docker compose down"
echo "  Health check: curl http://localhost:${BROWSERLESS_PORT}/json/version"
echo ""
echo "======================================================================"
