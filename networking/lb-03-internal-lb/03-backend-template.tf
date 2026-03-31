# ────────────────────────────────────────────────────────────────────
# Backend API 서버 시작 스크립트
# - /health: 헬스체크 엔드포인트
# - /api:    인스턴스 정보 JSON 반환 (로드밸런싱 확인용)
# ────────────────────────────────────────────────────────────────────
locals {
  backend_startup_script = <<-STARTUP
    #!/bin/bash
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y nginx curl

    INSTANCE_NAME=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/name" \
      -H "Metadata-Flavor: Google" || echo "unknown")
    ZONE=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/zone" \
      -H "Metadata-Flavor: Google" | awk -F'/' '{print $NF}' || echo "unknown")
    INSTANCE_IP=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip" \
      -H "Metadata-Flavor: Google" || echo "unknown")

    # 헬스체크 파일
    echo "OK" > /var/www/html/health

    # API 응답 파일 (JSON)
    cat > /var/www/html/api << 'APIJSON'
{"server":"SERVER_PH","zone":"ZONE_PH","ip":"IP_PH","status":"healthy","message":"Backend API Response OK"}
APIJSON

    sed -i "s/SERVER_PH/$INSTANCE_NAME/g" /var/www/html/api
    sed -i "s/ZONE_PH/$ZONE/g"            /var/www/html/api
    sed -i "s/IP_PH/$INSTANCE_IP/g"       /var/www/html/api

    # nginx 설정: /api → JSON, /health → plain text
    cat > /etc/nginx/sites-available/default << 'NGINXCONF'
server {
    listen 80;
    root /var/www/html;

    location /health {
        try_files /health =404;
        add_header Content-Type text/plain;
    }

    location /api {
        try_files /api =404;
        add_header Content-Type application/json;
        add_header Access-Control-Allow-Origin *;
    }

    location / {
        return 403 "Backend API Server - Direct access not allowed\n";
        add_header Content-Type text/plain;
    }
}
NGINXCONF

    systemctl enable nginx
    systemctl restart nginx
  STARTUP
}

# ────────────────────────────────────────────────────────────────────
# Backend API 인스턴스 템플릿
# - 외부 IP 없음 (Cloud NAT 경유)
# - 태그: backend-api
# ────────────────────────────────────────────────────────────────────
resource "google_compute_instance_template" "backend" {
  name_prefix  = "backend-api-template-"
  machine_type = "e2-medium"
  region       = var.region

  tags = ["backend-api"]

  disk {
    source_image = "debian-cloud/debian-12"
    boot         = true
    disk_size_gb = 20
    disk_type    = "pd-balanced"
    auto_delete  = true
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.backend.id
    # access_config 없음 → 외부 IP 미할당 (핵심: 인터넷 직접 접근 불가)
  }

  metadata = {
    startup-script = local.backend_startup_script
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_compute_router_nat.nat]
}
