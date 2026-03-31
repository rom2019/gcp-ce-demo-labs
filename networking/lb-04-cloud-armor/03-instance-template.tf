resource "google_compute_instance_template" "web" {
  name_prefix  = "armor-web-template-"
  machine_type = "e2-medium"
  tags         = ["web-server"]

  disk {
    source_image = "debian-cloud/debian-12"
    disk_type    = "pd-balanced"
    disk_size_gb = 20
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.main.id
    # 외부 IP 없음 — Cloud NAT 으로 아웃바운드
  }

  service_account {
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    startup-script = <<-STARTUP
      #!/bin/bash
      set -e
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      apt-get install -y python3

      INSTANCE_NAME=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/name" \
        -H "Metadata-Flavor: Google" || echo "unknown")
      ZONE=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/zone" \
        -H "Metadata-Flavor: Google" | awk -F'/' '{print $NF}' || echo "unknown")
      INSTANCE_IP=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip" \
        -H "Metadata-Flavor: Google" || echo "unknown")

      cat > /opt/server.py << 'PYEOF'
#!/usr/bin/env python3
import json, http.server, urllib.parse

INSTANCE_NAME = "INSTANCE_NAME_PH"
ZONE          = "ZONE_PH"
IP            = "IP_PH"

HTML = '''<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Cloud Armor WAF 데모</title>
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body { font-family:"Segoe UI",Arial,sans-serif; background:#0f1117; color:#e2e8f0; min-height:100vh; }
    header {
      background: linear-gradient(135deg, #c53030, #7b341e);
      padding: 1.2rem 2rem;
      display: flex; align-items: center; gap: 1rem;
    }
    header h1 { font-size:1.3rem; color:white; }
    .badge { background:#48bb78; color:white; padding:0.2rem 0.7rem; border-radius:12px; font-size:0.75rem; font-weight:bold; margin-left:auto; }
    .arch-bar {
      background:#1a202c; border-bottom:1px solid #2d3748;
      padding:0.8rem 2rem; font-family:monospace; font-size:0.82rem; color:#a0aec0;
      display:flex; align-items:center; gap:0.5rem; flex-wrap:wrap;
    }
    .arch-bar .box { border:1px solid; border-radius:6px; padding:0.3rem 0.8rem; font-size:0.8rem; }
    .arch-bar .box.browser { border-color:#4299e1; color:#90cdf4; background:#1a365d; }
    .arch-bar .box.armor  { border-color:#fc8181; color:#feb2b2; background:#742a2a; font-weight:bold; }
    .arch-bar .box.lb     { border-color:#f6ad55; color:#fbd38d; background:#744210; }
    .arch-bar .box.backend { border-color:#68d391; color:#9ae6b4; background:#276749; }
    .arch-bar .arrow { color:#68d391; font-size:1.1rem; }
    .main { max-width:1200px; margin:2rem auto; padding:0 1.5rem; display:grid; grid-template-columns:1fr 1fr; gap:1.5rem; }
    @media(max-width:768px){ .main{ grid-template-columns:1fr; } }
    .card { background:#1a202c; border:1px solid #2d3748; border-radius:12px; padding:1.5rem; }
    .card-title { font-size:0.75rem; font-weight:bold; text-transform:uppercase; letter-spacing:1.5px; color:#718096; margin-bottom:1rem; padding-bottom:0.5rem; border-bottom:1px solid #2d3748; }
    .info-row { display:flex; justify-content:space-between; align-items:center; padding:0.5rem 0; border-bottom:1px solid #2d3748; font-size:0.88rem; }
    .info-label { color:#718096; }
    .info-value { font-weight:600; font-family:monospace; }
    .info-value.green { color:#48bb78; }
    .info-value.blue  { color:#63b3ed; }
    .info-value.red   { color:#fc8181; }
    .btn-test { display:block; width:100%; padding:0.65rem 1rem; border:none; border-radius:8px; font-size:0.88rem; cursor:pointer; margin-bottom:0.5rem; transition:opacity 0.15s; text-align:left; }
    .btn-test:hover { opacity:0.82; }
    .btn-safe   { background:#276749; color:#9ae6b4; }
    .btn-danger { background:#742a2a; color:#fed7d7; }
    .result-box { margin-top:1rem; padding:1rem; border-radius:8px; font-family:monospace; font-size:0.82rem; min-height:70px; white-space:pre-wrap; }
    .result-box.safe    { background:#1c4532; border:1px solid #276749; color:#9ae6b4; }
    .result-box.blocked { background:#4a1515; border:1px solid #c53030; color:#fed7d7; }
    .result-box.pending { background:#1a202c; border:1px solid #2d3748; color:#718096; }
    .full-width { grid-column:1/-1; }
    .rules-table { width:100%; border-collapse:collapse; font-size:0.85rem; }
    .rules-table th { background:#2d3748; padding:0.7rem 1rem; text-align:left; font-size:0.73rem; letter-spacing:1px; text-transform:uppercase; color:#a0aec0; }
    .rules-table td { padding:0.7rem 1rem; border-bottom:1px solid #2d3748; vertical-align:top; }
    .rules-table tr:last-child td { border-bottom:none; }
    .tag { display:inline-block; padding:0.15rem 0.6rem; border-radius:4px; font-size:0.75rem; font-weight:bold; }
    .tag.deny     { background:#742a2a; color:#fed7d7; }
    .tag.throttle { background:#744210; color:#fbd38d; }
    .tag.allow    { background:#276749; color:#9ae6b4; }
    .log-entry { display:flex; align-items:center; gap:1rem; padding:0.45rem 0; border-bottom:1px solid #2d3748; font-size:0.82rem; font-family:monospace; }
    .log-entry:last-child { border-bottom:none; }
    .log-time { color:#718096; flex-shrink:0; }
    .log-label { flex:1; color:#e2e8f0; }
    .log-status.ok  { color:#48bb78; font-weight:bold; }
    .log-status.err { color:#fc8181; font-weight:bold; }
    #log-container { min-height:50px; color:#4a5568; font-size:0.85rem; }
  </style>
</head>
<body>

<header>
  <span style="font-size:1.5rem">&#128737;</span>
  <h1>Cloud Armor WAF &amp; DDoS 보호 데모</h1>
  <span class="badge">PROTECTED</span>
</header>

<div class="arch-bar">
  <span class="box browser">&#127760; 브라우저</span>
  <span class="arrow">&#8594;</span>
  <span class="box armor">&#128737; Cloud Armor</span>
  <span class="arrow">&#8594;</span>
  <span class="box lb">&#9878; Global LB (EXTERNAL_MANAGED)</span>
  <span class="arrow">&#8594;</span>
  <span class="box backend">&#128421; Backend VM</span>
  <span style="margin-left:auto;font-size:0.75rem;color:#718096">
    WAF &#10003;&nbsp; DDoS &#10003;&nbsp; Rate Limit &#10003;&nbsp; IP Blocklist &#10003;
  </span>
</div>

<div class="main">

  <div class="card">
    <div class="card-title">&#128100; 요청 정보</div>
    <div class="info-row"><span class="info-label">Backend VM</span><span class="info-value green" id="srv-name">로딩 중...</span></div>
    <div class="info-row"><span class="info-label">Zone</span><span class="info-value" id="srv-zone">-</span></div>
    <div class="info-row"><span class="info-label">VM Internal IP</span><span class="info-value blue" id="srv-ip">-</span></div>
    <div class="info-row"><span class="info-label">내 IP (X-Forwarded-For)</span><span class="info-value red" id="client-ip">-</span></div>
    <div class="info-row" style="border-bottom:none"><span class="info-label">User-Agent</span><span class="info-value" id="ua" style="font-size:0.72rem;word-break:break-all;max-width:60%%">-</span></div>
  </div>

  <div class="card">
    <div class="card-title">&#9889; WAF 공격 테스트</div>
    <p style="font-size:0.82rem;color:#718096;margin-bottom:1rem;">
      버튼 클릭 → Cloud Armor 앞으로 요청 전송<br>
      공격 패턴 탐지 시 Cloud Armor 가 즉시 차단 (HTTP 403)
    </p>
    <button class="btn-test btn-safe"   onclick="runTest('정상 요청',     '/api/info?test=hello')">&#9989; 정상 요청 테스트</button>
    <button class="btn-test btn-danger" onclick="runTest('SQL Injection', '/api/info?q=%27+OR+%271%27%3D%271')">&#128165; SQL Injection: ' OR '1'='1</button>
    <button class="btn-test btn-danger" onclick="runTest('XSS',           '/api/info?q=%3Cscript%3Ealert%281%29%3C%2Fscript%3E')">&#128165; XSS: &lt;script&gt;alert(1)&lt;/script&gt;</button>
    <button class="btn-test btn-danger" onclick="runTest('LFI',           '/api/info?path=..%2F..%2Fetc%2Fpasswd')">&#128165; LFI: ../../etc/passwd</button>
    <button class="btn-test btn-danger" onclick="runTest('RCE',           '/api/info?cmd=%3Bcat+%2Fetc%2Fpasswd')">&#128165; RCE: ; cat /etc/passwd</button>
    <div class="result-box pending" id="test-result">버튼을 눌러 WAF 테스트를 시작하세요...</div>
  </div>

  <div class="card full-width">
    <div class="card-title">&#128272; Cloud Armor 보안 정책 규칙</div>
    <table class="rules-table">
      <tr><th>우선순위</th><th>액션</th><th>조건</th><th>설명</th></tr>
      <tr>
        <td>1000</td>
        <td><span class="tag deny">DENY 403</span></td>
        <td style="font-family:monospace;font-size:0.82rem">src_ip == blocked_ip</td>
        <td style="font-size:0.82rem">IP 차단 목록 (Blocklist)<br><span style="color:#718096">var.blocked_ip 에 지정된 IP 즉시 차단</span></td>
      </tr>
      <tr>
        <td>2000</td>
        <td><span class="tag throttle">THROTTLE</span></td>
        <td style="font-family:monospace;font-size:0.82rem">rate &gt; 100/min per IP</td>
        <td style="font-size:0.82rem">Rate Limiting<br><span style="color:#718096">동일 IP 에서 분당 100회 초과 시 DENY 429</span></td>
      </tr>
      <tr>
        <td>3000</td>
        <td><span class="tag deny">DENY 403</span></td>
        <td style="font-family:monospace;font-size:0.82rem">sqli-stable</td>
        <td style="font-size:0.82rem">SQL Injection WAF<br><span style="color:#718096">OWASP CRS 기반 SQLi 패턴 탐지</span></td>
      </tr>
      <tr>
        <td>4000</td>
        <td><span class="tag deny">DENY 403</span></td>
        <td style="font-family:monospace;font-size:0.82rem">xss-stable</td>
        <td style="font-size:0.82rem">Cross-Site Scripting WAF<br><span style="color:#718096">OWASP CRS 기반 XSS 패턴 탐지</span></td>
      </tr>
      <tr>
        <td>5000</td>
        <td><span class="tag deny">DENY 403</span></td>
        <td style="font-family:monospace;font-size:0.82rem">lfi-stable</td>
        <td style="font-size:0.82rem">Local File Inclusion WAF<br><span style="color:#718096">경로 순회 공격 패턴 탐지</span></td>
      </tr>
      <tr>
        <td>6000</td>
        <td><span class="tag deny">DENY 403</span></td>
        <td style="font-family:monospace;font-size:0.82rem">rce-stable</td>
        <td style="font-size:0.82rem">Remote Code Execution WAF<br><span style="color:#718096">명령어 주입 패턴 탐지</span></td>
      </tr>
      <tr>
        <td>2147483647</td>
        <td><span class="tag allow">ALLOW</span></td>
        <td style="font-family:monospace;font-size:0.82rem">*</td>
        <td style="font-size:0.82rem">기본 허용 (Default Rule)</td>
      </tr>
    </table>
  </div>

  <div class="card full-width">
    <div class="card-title">&#128196; 테스트 결과 로그</div>
    <div id="log-container">테스트를 실행하면 결과가 여기 표시됩니다...</div>
  </div>

</div>

<script>
  var logCount = 0;

  function loadInfo() {
    fetch('/api/info')
      .then(function(r) { return r.json(); })
      .then(function(d) {
        document.getElementById('srv-name').textContent  = d.server     || '-';
        document.getElementById('srv-zone').textContent  = d.zone       || '-';
        document.getElementById('srv-ip').textContent    = d.ip         || '-';
        document.getElementById('client-ip').textContent = d.client_ip  || '-';
        document.getElementById('ua').textContent        = d.user_agent || '-';
      })
      .catch(function() {
        document.getElementById('srv-name').textContent = '로드 실패';
      });
  }

  function runTest(label, url) {
    var box = document.getElementById('test-result');
    box.className = 'result-box pending';
    box.textContent = label + ' 테스트 중...';
    var start = Date.now();
    fetch(url)
      .then(function(r) {
        var ms = Date.now() - start;
        var s  = r.status;
        if (s === 200) {
          box.className = 'result-box safe';
          box.textContent = '[' + label + '] HTTP 200 OK (' + ms + 'ms)\n정상 요청 — Cloud Armor 를 통과하였습니다.';
          addLog(label, '200 OK', true);
        } else if (s === 403) {
          box.className = 'result-box blocked';
          box.textContent = '[' + label + '] HTTP 403 Forbidden (' + ms + 'ms)\nCloud Armor WAF 에 의해 차단되었습니다.\n공격 패턴이 감지되어 Backend 에 도달하지 못했습니다.';
          addLog(label, '403 Blocked', false);
        } else if (s === 429) {
          box.className = 'result-box blocked';
          box.textContent = '[' + label + '] HTTP 429 Too Many Requests (' + ms + 'ms)\nCloud Armor Rate Limiting 에 의해 차단되었습니다.';
          addLog(label, '429 Rate Limited', false);
        } else {
          box.className = 'result-box pending';
          box.textContent = '[' + label + '] HTTP ' + s + ' (' + ms + 'ms)';
          addLog(label, 'HTTP ' + s, s < 400);
        }
      })
      .catch(function(err) {
        box.className = 'result-box blocked';
        box.textContent = '[' + label + '] 오류: ' + err.message;
        addLog(label, 'ERROR', false);
      });
  }

  function addLog(label, status, ok) {
    var c = document.getElementById('log-container');
    if (logCount === 0) c.innerHTML = '';
    logCount++;
    var now = new Date();
    var t   = now.getHours() + ':' +
              String(now.getMinutes()).padStart(2, '0') + ':' +
              String(now.getSeconds()).padStart(2, '0');
    var el = document.createElement('div');
    el.className = 'log-entry';
    el.innerHTML = '<span class="log-time">' + t + '</span>' +
                   '<span class="log-label">' + label + '</span>' +
                   '<span class="log-status ' + (ok ? 'ok' : 'err') + '">' +
                   (ok ? '&#9989;' : '&#10060;') + ' ' + status + '</span>';
    c.insertBefore(el, c.firstChild);
  }

  window.addEventListener('load', loadInfo);
</script>

</body>
</html>'''

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)

        if parsed.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')

        elif parsed.path == '/api/info':
            data = {
                'server':     INSTANCE_NAME,
                'zone':       ZONE,
                'ip':         IP,
                'client_ip':  self.headers.get('X-Forwarded-For', self.client_address[0]),
                'user_agent': self.headers.get('User-Agent', '-'),
            }
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())

        else:
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(HTML.encode())

if __name__ == '__main__':
    http.server.HTTPServer(('', 80), Handler).serve_forever()
PYEOF

      sed -i "s/INSTANCE_NAME_PH/$INSTANCE_NAME/g" /opt/server.py
      sed -i "s/ZONE_PH/$ZONE/g"                   /opt/server.py
      sed -i "s/IP_PH/$INSTANCE_IP/g"              /opt/server.py

      cat > /etc/systemd/system/webserver.service << 'SVCEOF'
[Unit]
Description=Cloud Armor Demo Web Server
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SVCEOF

      systemctl daemon-reload
      systemctl enable --now webserver
    STARTUP
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_project_service.apis]
}
