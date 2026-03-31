# ────────────────────────────────────────────────────────────────────
# Cloud Armor Security Policy
#
# 규칙 우선순위 (낮은 숫자 = 높은 우선순위):
#   1000 — IP 차단 목록 (Blocklist)
#   2000 — Rate Limiting (분당 100회 초과 시 429)
#   3000 — SQLi WAF (OWASP CRS)
#   4000 — XSS WAF (OWASP CRS)
#   5000 — LFI WAF
#   6000 — RCE WAF
#   2147483647 — 기본 허용
#
# ※ Cloud Armor Standard 티어 필요 (WAF 규칙, Rate Limiting)
# ────────────────────────────────────────────────────────────────────
resource "google_compute_security_policy" "main" {
  name        = "web-security-policy"
  description = "Cloud Armor WAF + DDoS 보호 데모 정책"

  # DDoS 적응형 보호 — 비정상 L7 트래픽 자동 탐지
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }

  # ── Rule 1000: IP 차단 목록 ────────────────────────────────────────
  # var.blocked_ip 에 지정된 IP 는 WAF 평가 없이 즉시 차단
  rule {
    action      = "deny(403)"
    priority    = 1000
    description = "IP Blocklist — var.blocked_ip 차단"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = [var.blocked_ip]
      }
    }
  }

  # ── Rule 2000: SQL Injection ────────────────────────────────────────
  # [주의] WAF 규칙은 Rate Limiting 보다 반드시 높은 우선순위여야 함
  # throttle 의 conform_action=allow 는 평가를 즉시 종료하므로
  # Rate Limiting 이 WAF 앞에 오면 모든 정상 요청에서 WAF 가 건너뜀
  rule {
    action      = "deny(403)"
    priority    = 2000
    description = "SQL Injection 탐지 및 차단 (OWASP CRS sqli-stable)"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable')"
      }
    }
  }

  # ── Rule 3000: XSS ─────────────────────────────────────────────────
  rule {
    action      = "deny(403)"
    priority    = 3000
    description = "Cross-Site Scripting 탐지 및 차단 (OWASP CRS xss-stable)"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-stable')"
      }
    }
  }

  # ── Rule 4000: LFI ─────────────────────────────────────────────────
  rule {
    action      = "deny(403)"
    priority    = 4000
    description = "Local File Inclusion 탐지 및 차단 (lfi-stable)"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-stable')"
      }
    }
  }

  # ── Rule 5000: RCE ─────────────────────────────────────────────────
  rule {
    action      = "deny(403)"
    priority    = 5000
    description = "Remote Code Execution 탐지 및 차단 (rce-stable)"

    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rce-stable')"
      }
    }
  }

  # ── Rule 6000: Rate Limiting ────────────────────────────────────────
  # WAF 규칙 이후에 배치 — 공격 패턴이 아닌 요청에 대해 속도 제한 적용
  rule {
    action      = "throttle"
    priority    = 6000
    description = "Rate Limiting — 분당 100회 초과 시 DENY 429"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"

      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }

      enforce_on_key = "IP"
    }
  }

  # ── Default Rule: Allow ─────────────────────────────────────────────
  rule {
    action      = "allow"
    priority    = 2147483647
    description = "기본 허용 (Default Rule)"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }

  depends_on = [google_project_service.apis]
}
