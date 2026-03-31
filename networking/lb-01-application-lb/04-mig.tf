# ────────────────────────────────────────────────────────────────────
# Regional Managed Instance Group (MIG)
# 리전 내 여러 존에 인스턴스를 자동 분산 → 가용성 확보
# ────────────────────────────────────────────────────────────────────
resource "google_compute_region_instance_group_manager" "shop" {
  name               = "shop-mig"
  region             = var.region
  base_instance_name = "shop"
  target_size        = 2

  version {
    instance_template = google_compute_instance_template.shop.id
  }

  # LB가 참조하는 named port (backend service의 port_name과 일치)
  named_port {
    name = "http"
    port = 80
  }

  # 헬스체크 기반 자동 복구: 비정상 인스턴스 자동 교체
  auto_healing_policies {
    health_check      = google_compute_health_check.http.id
    initial_delay_sec = 180 # 인스턴스 시작 스크립트 완료 대기 (약 3분)
  }

}

# ────────────────────────────────────────────────────────────────────
# Auto Scaler: CPU 사용률 기반 자동 확장/축소
# ────────────────────────────────────────────────────────────────────
resource "google_compute_region_autoscaler" "shop" {
  name   = "shop-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.shop.id

  autoscaling_policy {
    min_replicas    = 2  # 최소 2개 (멀티존 가용성)
    max_replicas    = 10 # 최대 10개
    cooldown_period = 60 # 스케일 아웃 후 안정화 대기 시간(초)

    cpu_utilization {
      target = 0.7 # CPU 70% 초과 시 스케일 아웃
    }
  }
}
