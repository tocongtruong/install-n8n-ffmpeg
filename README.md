# N8N + SSL + FFmpeg Auto Installer Cập nhật: 13/02/2026


## 1. Cài đặt N8N + SSL + FFmpeg

```bash
cd /tmp && curl -sSL https://raw.githubusercontent.com/tocongtruong/install-n8n-ffmpeg/refs/heads/main/auto_cai_dat_n8n.sh | tr -d '\r' > install_n8n.sh && chmod +x install_n8n.sh && sudo bash install_n8n.sh
```

## 2. Cài đặt Browserless Chrome (Puppeteer Server)

```bash
cd /tmp && curl -sSL https://raw.githubusercontent.com/tocongtruong/install-n8n-ffmpeg/refs/heads/main/install_browserless.sh | tr -d '\r' > install_browserless.sh && chmod +x install_browserless.sh && sudo bash install_browserless.sh
```

**Bao gồm:**
- Browserless Chromium (đầy đủ thư viện)
- Tự động kết nối Docker network với n8n
- Port mặc định: `3000`

---

## 3. Cách dùng Browserless trong N8N

### Cách 1: Node `Code` (Puppeteer)

```javascript
const puppeteer = require('puppeteer-core');
const browser = await puppeteer.connect({
  browserWSEndpoint: 'ws://browserless:3000',
});
const page = await browser.newPage();
await page.goto('https://example.com');
const screenshot = await page.screenshot();
await browser.close();
```

### Cách 2: Node `HTTP Request` (REST API)

| Chức năng | Method | URL | Body |
|-----------|--------|-----|------|
| Chụp ảnh trang web | `POST` | `http://browserless:3000/screenshot` | `{"url": "https://example.com"}` |
| Tạo PDF | `POST` | `http://browserless:3000/pdf` | `{"url": "https://example.com"}` |
| Lấy nội dung HTML | `POST` | `http://browserless:3000/content` | `{"url": "https://example.com"}` |
| Scrape dữ liệu | `POST` | `http://browserless:3000/scrape` | `{"url": "https://example.com", "elements": [{"selector": "h1"}]}` |

---

## 4. Lệnh quản lý

### N8N

```bash
# Xem logs
cd /home/n8n && docker compose logs -f

# Restart
/home/n8n/restart-n8n.sh

# Backup
/home/n8n/backup-n8n.sh

# Cập nhật thủ công
/home/n8n/update-n8n.sh
```

### Browserless

```bash
# Xem logs
cd /home/browserless && docker compose logs -f

# Restart
cd /home/browserless && docker compose restart

# Dừng
cd /home/browserless && docker compose down

# Health check
curl http://localhost:3000/json/version
```
