# ────────────────────────────────────────────────────────────────────
# 게임 서버 시작 스크립트
# ────────────────────────────────────────────────────────────────────
locals {
  startup_script = <<-STARTUP
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
    START_EPOCH=$(date +%s)

    # 헬스체크 엔드포인트
    echo "OK" > /var/www/html/health

    # 게임 서버 상태 페이지
    cat > /var/www/html/index.html << 'GAMEHTML'
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>GCP Game Server</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #0a0e1a;
      color: #c0c8e0;
      font-family: 'Courier New', monospace;
      min-height: 100vh;
      padding: 1.5rem;
    }

    .header {
      display: flex;
      align-items: center;
      gap: 1rem;
      padding: 1rem 1.5rem;
      background: #111827;
      border: 1px solid #1e3a5f;
      border-radius: 10px;
      margin-bottom: 1.5rem;
    }
    .header h1 { font-size: 1.4rem; color: #00ff88; letter-spacing: 2px; }
    .status-dot {
      width: 12px; height: 12px;
      border-radius: 50%;
      background: #00ff88;
      box-shadow: 0 0 8px #00ff88;
      animation: pulse 1.5s infinite;
    }
    @keyframes pulse { 0%%,100%%{opacity:1} 50%%{opacity:0.4} }
    .status-text { color: #00ff88; font-size: 0.85rem; margin-left: auto; }

    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 1.2rem; margin-bottom: 1.2rem; }
    @media(max-width:700px){ .grid{ grid-template-columns:1fr; } }

    .card {
      background: #111827;
      border: 1px solid #1e3a5f;
      border-radius: 10px;
      padding: 1.2rem 1.5rem;
    }
    .card-title {
      font-size: 0.7rem;
      color: #4a7fa5;
      letter-spacing: 2px;
      text-transform: uppercase;
      margin-bottom: 1rem;
      border-bottom: 1px solid #1e3a5f;
      padding-bottom: 0.5rem;
    }
    .info-row { display: flex; justify-content: space-between; margin: 0.5rem 0; font-size: 0.88rem; }
    .info-label { color: #4a7fa5; }
    .info-value { color: #00b8ff; font-weight: bold; }
    .info-value.green { color: #00ff88; }
    .info-value.orange { color: #ff9500; }

    .metric-grid { display: grid; grid-template-columns: repeat(3,1fr); gap: 1rem; }
    .metric { text-align: center; }
    .metric-val { font-size: 1.8rem; font-weight: bold; color: #00ff88; }
    .metric-val.blue { color: #00b8ff; }
    .metric-val.orange { color: #ff9500; }
    .metric-label { font-size: 0.7rem; color: #4a7fa5; margin-top: 0.3rem; letter-spacing: 1px; }

    .session-box {
      background: #0d1f0d;
      border: 1px solid #00ff4420;
      border-left: 4px solid #00ff88;
      border-radius: 8px;
      padding: 1.2rem 1.5rem;
      margin-bottom: 1.2rem;
    }
    .session-box .title { color: #00ff88; font-size: 0.8rem; letter-spacing: 2px; margin-bottom: 0.8rem; }
    .session-id { font-size: 1.1rem; color: #00ff88; letter-spacing: 3px; word-break: break-all; }
    .session-hint { font-size: 0.78rem; color: #4a7fa5; margin-top: 0.6rem; }

    .nlb-box {
      background: #0d1525;
      border: 1px solid #00b8ff20;
      border-left: 4px solid #00b8ff;
      border-radius: 8px;
      padding: 1.2rem 1.5rem;
      margin-bottom: 1.2rem;
    }
    .nlb-box .title { color: #00b8ff; font-size: 0.8rem; letter-spacing: 2px; margin-bottom: 0.8rem; }
    .nlb-table { width: 100%; font-size: 0.82rem; border-collapse: collapse; }
    .nlb-table th { color: #4a7fa5; text-align: left; padding: 0.3rem 0.5rem; border-bottom: 1px solid #1e3a5f; }
    .nlb-table td { padding: 0.4rem 0.5rem; }
    .nlb-table .good { color: #00ff88; }
    .nlb-table .bad { color: #ff4444; }
    .nlb-table .tag {
      background: #00b8ff22;
      color: #00b8ff;
      padding: 0.1rem 0.5rem;
      border-radius: 4px;
      font-size: 0.75rem;
    }

    .mistake-box {
      background: #1f0d0d;
      border: 1px solid #ff444420;
      border-left: 4px solid #ff4444;
      border-radius: 8px;
      padding: 1.2rem 1.5rem;
      margin-bottom: 1.2rem;
    }
    .mistake-box .title { color: #ff4444; font-size: 0.8rem; letter-spacing: 2px; margin-bottom: 0.8rem; }
    .mistake-item { margin: 0.6rem 0; font-size: 0.85rem; }
    .mistake-item .label { color: #ff6666; }
    .mistake-item .fix { color: #00ff88; font-size: 0.8rem; margin-top: 0.2rem; }

    footer {
      text-align: center;
      color: #1e3a5f;
      font-size: 0.75rem;
      margin-top: 1.5rem;
      letter-spacing: 1px;
    }
  </style>
</head>
<body>

<div class="header">
  <div class="status-dot"></div>
  <h1>&#9654; GCP GAME SERVER</h1>
  <span class="status-text">ONLINE &#9632; REGIONAL PASSTHROUGH NLB</span>
</div>

<!-- 서버 정보 + 실시간 메트릭 -->
<div class="grid">
  <div class="card">
    <div class="card-title">&#9632; Server Instance Info</div>
    <div class="info-row"><span class="info-label">INSTANCE</span><span class="info-value green">INSTANCE_NAME_PH</span></div>
    <div class="info-row"><span class="info-label">ZONE</span><span class="info-value">ZONE_PH</span></div>
    <div class="info-row"><span class="info-label">INTERNAL IP</span><span class="info-value">IP_PH</span></div>
    <div class="info-row"><span class="info-label">STARTED</span><span class="info-value orange">START_TIME_PH</span></div>
  </div>

  <div class="card">
    <div class="card-title">&#9632; Live Server Metrics</div>
    <div class="metric-grid">
      <div class="metric">
        <div class="metric-val" id="players">--</div>
        <div class="metric-label">PLAYERS<br>ONLINE</div>
      </div>
      <div class="metric">
        <div class="metric-val blue" id="uptime">--</div>
        <div class="metric-label">SERVER<br>UPTIME(s)</div>
      </div>
      <div class="metric">
        <div class="metric-val orange" id="ping">--</div>
        <div class="metric-label">AVG PING<br>(ms)</div>
      </div>
    </div>
  </div>
</div>

<!-- 세션 정보 (NLB 세션 어피니티 확인용) -->
<div class="session-box">
  <div class="title">&#9632; SESSION AFFINITY DEMO (CLIENT_IP &#8594; 고정 서버 라우팅)</div>
  <div>현재 연결된 서버: <span class="session-id">INSTANCE_NAME_PH</span></div>
  <div class="session-hint">
    &#128161; F5(새로고침)를 반복해도 같은 서버(INSTANCE_NAME_PH)로 연결됩니다.<br>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NLB의 session_affinity = "CLIENT_IP" 설정이 동일 클라이언트 IP를 동일 서버로 고정합니다.<br>
    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;다른 브라우저나 네트워크에서 접속하면 다른 서버로 연결될 수 있습니다.
  </div>
</div>

<!-- NLB vs Application LB 비교 -->
<div class="nlb-box">
  <div class="title">&#9632; NETWORK LB vs APPLICATION LB</div>
  <table class="nlb-table">
    <tr>
      <th>항목</th>
      <th>Network LB (이 실습)</th>
      <th>Application LB (lb-01)</th>
    </tr>
    <tr>
      <td>레이어</td>
      <td class="good">L4 (TCP/UDP)</td>
      <td>L7 (HTTP/HTTPS)</td>
    </tr>
    <tr>
      <td>프록시 여부</td>
      <td class="good">Passthrough (직접 전달)</td>
      <td>Proxy (LB가 중개)</td>
    </tr>
    <tr>
      <td>클라이언트 IP 보존</td>
      <td class="good">&#10003; 보존</td>
      <td>X-Forwarded-For 헤더</td>
    </tr>
    <tr>
      <td>지연시간</td>
      <td class="good">&#9650;&#9650; 매우 낮음</td>
      <td>&#9650; 낮음</td>
    </tr>
    <tr>
      <td>범위</td>
      <td><span class="tag">REGIONAL</span></td>
      <td><span class="tag">GLOBAL</span></td>
    </tr>
    <tr>
      <td>세션 어피니티</td>
      <td class="good">CLIENT_IP 지원</td>
      <td>Cookie / CLIENT_IP</td>
    </tr>
    <tr>
      <td>사용 사례</td>
      <td class="good">게임, 스트리밍, VoIP</td>
      <td>웹앱, API, CDN</td>
    </tr>
  </table>
</div>

<!-- 자주 하는 실수 -->
<div class="mistake-box">
  <div class="title">&#9888; 자주 하는 실수</div>
  <div class="mistake-item">
    <div class="label">&#10007; 실수 1: Regional NLB 에 Global Forwarding Rule 사용</div>
    <div class="fix">&#10003; 수정: NLB 는 반드시 google_compute_forwarding_rule (리전) 사용.
      google_compute_global_forwarding_rule 은 Global Application LB / Proxy NLB 전용.</div>
  </div>
  <div class="mistake-item">
    <div class="label">&#10007; 실수 2: session_affinity 미설정 → 게임 세션 끊김</div>
    <div class="fix">&#10003; 수정: backend_service 에 session_affinity = "CLIENT_IP" 설정.
      게임/스트리밍에서 미설정 시 매 연결마다 다른 서버로 라우팅되어 세션 데이터 유실.</div>
  </div>
</div>

<footer>GCP Network Load Balancer 실습 &mdash; Regional External Passthrough NLB (Backend Service 방식)</footer>

<script>
  var startEpoch = START_EPOCH_PH;
  var basePlayers = Math.floor(Math.random() * 30) + 20;

  function update() {
    var now = Math.floor(Date.now() / 1000);
    document.getElementById('uptime').textContent = now - startEpoch;
    document.getElementById('players').textContent = basePlayers + Math.floor(Math.sin(now * 0.3) * 5);
    document.getElementById('ping').textContent = Math.floor(Math.random() * 20 + 15);
  }

  update();
  setInterval(update, 1000);
</script>

</body>
</html>
GAMEHTML

    sed -i "s/INSTANCE_NAME_PH/$INSTANCE_NAME/g" /var/www/html/index.html
    sed -i "s/ZONE_PH/$ZONE/g"                   /var/www/html/index.html
    sed -i "s/IP_PH/$INSTANCE_IP/g"              /var/www/html/index.html
    sed -i "s/START_TIME_PH/$(date '+%Y-%m-%d %H:%M UTC')/g" /var/www/html/index.html
    sed -i "s/START_EPOCH_PH/$START_EPOCH/g"     /var/www/html/index.html

    systemctl enable nginx
    systemctl restart nginx
  STARTUP
}

# ────────────────────────────────────────────────────────────────────
# 인스턴스 템플릿
# ────────────────────────────────────────────────────────────────────
resource "google_compute_instance_template" "game" {
  name_prefix  = "game-template-"
  machine_type = "e2-medium"
  region       = var.region

  tags = ["game-server"]

  disk {
    source_image = "debian-cloud/debian-12"
    boot         = true
    disk_size_gb = 20
    disk_type    = "pd-balanced"
    auto_delete  = true
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.subnet.id
    # 외부 IP 없음 — Cloud NAT 경유
  }

  metadata = {
    startup-script = local.startup_script
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_compute_router_nat.nat]
}
