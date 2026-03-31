# ────────────────────────────────────────────────────────────────────
# Backend API Regional MIG — 3개 고정 (마이크로서비스 시나리오)
# ────────────────────────────────────────────────────────────────────
resource "google_compute_region_instance_group_manager" "backend" {
  name               = "backend-api-mig"
  region             = var.region
  base_instance_name = "backend-api"
  target_size        = 3 # 시나리오 요건: Backend API 서버 3대

  version {
    instance_template = google_compute_instance_template.backend.id
  }

  auto_healing_policies {
    health_check      = google_compute_region_health_check.http.id
    initial_delay_sec = 180
  }
}
