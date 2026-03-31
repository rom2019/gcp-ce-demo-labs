# ────────────────────────────────────────────────────────────────────
# Frontend 서비스 VM
# - 외부 IP 있음 (브라우저 데모 접속용)
# - nginx: 외부 요청을 Internal LB VIP 로 프록시
# - Internal LB IP 를 인스턴스 메타데이터로 주입 → startup script 에서 참조
# ────────────────────────────────────────────────────────────────────
locals {
  frontend_startup_script = <<-STARTUP
    #!/bin/bash
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y nginx curl

    # 인스턴스 메타데이터 조회
    INSTANCE_NAME=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/name" \
      -H "Metadata-Flavor: Google" || echo "unknown")
    ZONE=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/zone" \
      -H "Metadata-Flavor: Google" | awk -F'/' '{print $NF}' || echo "unknown")
    INSTANCE_IP=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip" \
      -H "Metadata-Flavor: Google" || echo "unknown")

    # Internal LB VIP (Terraform 이 메타데이터로 주입)
    ILB_IP=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/ilb-ip" \
      -H "Metadata-Flavor: Google" || echo "UNKNOWN")

    # ── nginx: /api → Internal LB VIP 프록시 설정 ──────────────────
    cat > /etc/nginx/sites-available/default << 'NGINXCONF'
server {
    listen 80;
    root /var/www/html;

    # /api 요청을 Internal LB VIP 로 프록시
    location /api {
        proxy_pass http://ILB_IP_PLACEHOLDER/api;
        proxy_set_header Host $host;
        proxy_connect_timeout 5s;
        proxy_read_timeout 10s;
        add_header X-Proxied-Via "frontend-nginx";
    }

    location /health {
        return 200 'OK';
        add_header Content-Type text/plain;
    }

    location / {
        index index.html;
    }
}
NGINXCONF

    # Internal LB IP 를 nginx 설정에 주입
    sed -i "s/ILB_IP_PLACEHOLDER/$ILB_IP/g" /etc/nginx/sites-available/default

    # ── 데모 HTML 페이지 ───────────────────────────────────────────
    cat > /var/www/html/index.html << 'FRONTHTML'
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>마이크로서비스 Internal LB 데모</title>
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body { font-family: 'Segoe UI', Arial, sans-serif; background:#f0f4f8; color:#2d3748; }

    header {
      background: linear-gradient(135deg, #1a365d, #2b6cb0);
      color: white;
      padding: 1.2rem 2rem;
      display: flex; align-items: center; gap: 1rem;
    }
    header h1 { font-size: 1.3rem; }
    .badge {
      background: #48bb78;
      color: white;
      padding: 0.2rem 0.7rem;
      border-radius: 12px;
      font-size: 0.75rem;
      font-weight: bold;
      margin-left: auto;
    }

    .arch-bar {
      background: #2d3748;
      color: #e2e8f0;
      padding: 0.8rem 2rem;
      font-family: monospace;
      font-size: 0.85rem;
      display: flex;
      align-items: center;
      gap: 0.5rem;
      flex-wrap: wrap;
    }
    .arch-bar .box {
      background: #4a5568;
      border: 1px solid #718096;
      border-radius: 6px;
      padding: 0.3rem 0.8rem;
    }
    .arch-bar .box.green { background:#276749; border-color:#48bb78; color:#9ae6b4; }
    .arch-bar .box.blue  { background:#2a4365; border-color:#4299e1; color:#90cdf4; }
    .arch-bar .box.red   { background:#742a2a; border-color:#fc8181; color:#fed7d7; }
    .arch-bar .arrow { color: #68d391; font-size: 1.1rem; }

    .main { max-width: 1100px; margin: 2rem auto; padding: 0 1.5rem; display: grid; grid-template-columns: 1fr 1fr; gap: 1.5rem; }
    @media(max-width:768px){ .main{ grid-template-columns:1fr; } }

    .card {
      background: white;
      border-radius: 12px;
      padding: 1.5rem;
      box-shadow: 0 2px 8px rgba(0,0,0,0.08);
    }
    .card-title {
      font-size: 0.75rem;
      font-weight: bold;
      text-transform: uppercase;
      letter-spacing: 1.5px;
      color: #718096;
      margin-bottom: 1rem;
      padding-bottom: 0.5rem;
      border-bottom: 2px solid #e2e8f0;
    }
    .info-row { display:flex; justify-content:space-between; padding:0.4rem 0; border-bottom:1px solid #f7fafc; font-size:0.9rem; }
    .info-label { color:#718096; }
    .info-value { font-weight:600; color:#2d3748; }
    .info-value.green { color:#276749; }
    .info-value.blue  { color:#2b6cb0; }
    .info-value.orange { color:#c05621; }

    .btn-call {
      width: 100%;
      background: #2b6cb0;
      color: white;
      border: none;
      padding: 0.8rem;
      border-radius: 8px;
      font-size: 1rem;
      cursor: pointer;
      margin-top: 1rem;
      transition: background 0.15s;
    }
    .btn-call:hover { background: #2c5282; }
    .btn-call:disabled { background: #a0aec0; cursor: not-allowed; }

    .response-box {
      background: #f7fafc;
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      padding: 1rem;
      margin-top: 1rem;
      font-family: monospace;
      font-size: 0.85rem;
      min-height: 80px;
      white-space: pre-wrap;
      color: #2d3748;
    }
    .response-box.success { border-color: #48bb78; background: #f0fff4; }
    .response-box.error   { border-color: #fc8181; background: #fff5f5; }
    .call-count { font-size:0.78rem; color:#718096; margin-top:0.4rem; text-align:right; }

    .security-list { list-style:none; }
    .security-list li {
      padding: 0.6rem 0;
      border-bottom: 1px solid #f7fafc;
      font-size: 0.9rem;
      display: flex;
      align-items: flex-start;
      gap: 0.5rem;
    }
    .security-list .icon-ok  { color:#48bb78; font-weight:bold; flex-shrink:0; }
    .security-list .icon-no  { color:#fc8181; font-weight:bold; flex-shrink:0; }

    .ilb-box {
      background: #ebf8ff;
      border: 1px solid #90cdf4;
      border-left: 4px solid #2b6cb0;
      border-radius: 8px;
      padding: 1rem 1.2rem;
      font-size: 0.88rem;
      margin-top: 1rem;
    }
    .ilb-box strong { color: #2b6cb0; }

    .full-width { grid-column: 1 / -1; }
    .fw-table { width:100%; border-collapse:collapse; font-size:0.85rem; }
    .fw-table th { background:#edf2f7; padding:0.6rem 0.8rem; text-align:left; font-size:0.75rem; letter-spacing:1px; text-transform:uppercase; color:#4a5568; }
    .fw-table td { padding:0.6rem 0.8rem; border-bottom:1px solid #e2e8f0; }
    .tag { display:inline-block; padding:0.15rem 0.5rem; border-radius:4px; font-size:0.75rem; font-weight:bold; }
    .tag.green { background:#c6f6d5; color:#276749; }
    .tag.red   { background:#fed7d7; color:#c53030; }
    .tag.blue  { background:#bee3f8; color:#2c5282; }
  </style>
</head>
<body>

<header>
  <span>&#127760;</span>
  <h1>마이크로서비스 Internal Load Balancer 데모</h1>
  <span class="badge">FRONTEND SERVICE</span>
</header>

<div class="arch-bar">
  <span>&#127760; 브라우저</span>
  <span class="arrow">&#8594;</span>
  <span class="box green">Frontend VM (외부 IP)</span>
  <span class="arrow">&#8594; nginx proxy &#8594;</span>
  <span class="box blue">Internal LB VIP (ILB_IP_PH)</span>
  <span class="arrow">&#8594;</span>
  <span class="box red">Backend API &#215;3 (외부 IP 없음)</span>
</div>

<div class="main">

  <!-- Frontend 서버 정보 -->
  <div class="card">
    <div class="card-title">&#128421; Frontend 서버 정보</div>
    <div class="info-row"><span class="info-label">인스턴스명</span><span class="info-value green">FRONTEND_NAME_PH</span></div>
    <div class="info-row"><span class="info-label">Zone</span><span class="info-value">FRONTEND_ZONE_PH</span></div>
    <div class="info-row"><span class="info-label">내부 IP</span><span class="info-value blue">FRONTEND_IP_PH</span></div>
    <div class="info-row"><span class="info-label">역할</span><span class="info-value">nginx Reverse Proxy</span></div>
    <div class="ilb-box">
      <strong>Internal LB VIP:</strong> ILB_IP_PH<br>
      <span style="color:#4a5568">이 IP 는 Private IP 입니다. 인터넷에서 직접 접근 불가.</span>
    </div>
  </div>

  <!-- Backend API 호출 -->
  <div class="card">
    <div class="card-title">&#9654; Backend API 호출 테스트</div>
    <p style="font-size:0.88rem;color:#4a5568;">
      버튼을 클릭하면 Frontend → Internal LB → Backend API 순서로 요청이 전달됩니다.<br>
      매 호출마다 다른 Backend 서버가 응답할 수 있습니다.
    </p>
    <button class="btn-call" id="callBtn" onclick="callBackend()">&#8635; Backend API 호출</button>
    <div class="response-box" id="responseBox">버튼을 눌러 Backend API 를 호출하세요...</div>
    <div class="call-count" id="callCount"></div>
  </div>

  <!-- 보안: 외부 접근 불가 확인 -->
  <div class="card">
    <div class="card-title">&#128274; 보안: Backend 외부 접근 차단 확인</div>
    <ul class="security-list">
      <li><span class="icon-ok">&#10003;</span><div><strong>Backend VM — 외부 IP 없음</strong><br><span style="font-size:0.8rem;color:#718096">access_config 미설정 → 인터넷에서 직접 접근 불가</span></div></li>
      <li><span class="icon-ok">&#10003;</span><div><strong>Internal LB VIP — Private IP 전용</strong><br><span style="font-size:0.8rem;color:#718096">ILB_IP_PH 는 VPC 내부에서만 라우팅</span></div></li>
      <li><span class="icon-ok">&#10003;</span><div><strong>Frontend 가 유일한 진입점</strong><br><span style="font-size:0.8rem;color:#718096">외부 → Frontend → Internal LB → Backend</span></div></li>
      <li><span class="icon-no">&#10007;</span><div><strong>Backend 직접 접속 시도 → 실패</strong><br><span style="font-size:0.8rem;color:#718096">외부에서 Backend IP 직접 호출 불가 (외부 IP 없음)</span></div></li>
    </ul>
  </div>

  <!-- 방화벽 규칙 -->
  <div class="card">
    <div class="card-title">&#128272; 핵심 방화벽 규칙</div>
    <table class="fw-table">
      <tr><th>규칙명</th><th>대상</th><th>목적</th></tr>
      <tr>
        <td>micro-allow-health-check</td>
        <td><span class="tag blue">backend-api</span></td>
        <td style="font-size:0.8rem">GCP 헬스체크 프로브 허용<br><span style="color:#c05621">없으면 Internal LB 동작 안 함!</span></td>
      </tr>
      <tr>
        <td>micro-allow-internal</td>
        <td><span class="tag blue">backend-api</span></td>
        <td style="font-size:0.8rem">Frontend → Backend VPC 내부 통신</td>
      </tr>
      <tr>
        <td>micro-allow-frontend-http</td>
        <td><span class="tag green">frontend</span></td>
        <td style="font-size:0.8rem">외부 브라우저 → Frontend 접속</td>
      </tr>
    </table>
  </div>

</div>

<script>
  var callCount = 0;

  function callBackend() {
    var btn = document.getElementById('callBtn');
    var box = document.getElementById('responseBox');
    var cnt = document.getElementById('callCount');

    btn.disabled = true;
    btn.textContent = '호출 중...';
    box.className = 'response-box';
    box.textContent = '요청 전송 중...';

    fetch('/api')
      .then(function(r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function(data) {
        callCount++;
        box.className = 'response-box success';
        box.textContent = JSON.stringify(data, null, 2);
        cnt.textContent = '총 ' + callCount + '회 호출 | 마지막 응답: ' + data.server + ' (' + data.zone + ')';
      })
      .catch(function(err) {
        callCount++;
        box.className = 'response-box error';
        box.textContent = '오류: ' + err.message + '\n\nBackend 가 아직 준비 중일 수 있습니다. 잠시 후 다시 시도하세요.';
        cnt.textContent = '총 ' + callCount + '회 호출';
      })
      .finally(function() {
        btn.disabled = false;
        btn.textContent = '↻ Backend API 호출';
      });
  }
</script>

</body>
</html>
FRONTHTML

    # 플레이스홀더 교체
    sed -i "s/FRONTEND_NAME_PH/$INSTANCE_NAME/g" /var/www/html/index.html
    sed -i "s/FRONTEND_ZONE_PH/$ZONE/g"          /var/www/html/index.html
    sed -i "s/FRONTEND_IP_PH/$INSTANCE_IP/g"     /var/www/html/index.html
    sed -i "s/ILB_IP_PH/$ILB_IP/g"              /var/www/html/index.html

    systemctl enable nginx
    systemctl restart nginx
  STARTUP
}

resource "google_compute_instance" "frontend" {
  name         = "frontend-service"
  machine_type = "e2-medium"
  zone         = "${var.region}-a"

  tags = ["frontend"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.frontend.id
    access_config {} # 외부 IP 할당 (데모 접속용)
  }

  metadata = {
    startup-script = local.frontend_startup_script
    ilb-ip         = google_compute_forwarding_rule.internal.ip_address
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  depends_on = [
    google_compute_router_nat.nat,
    google_compute_forwarding_rule.internal,
    google_project_organization_policy.vm_external_ip,
  ]
}
