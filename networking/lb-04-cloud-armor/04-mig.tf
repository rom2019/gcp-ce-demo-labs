# ────────────────────────────────────────────────────────────────────
# Regional MIG — 2대 고정
# ────────────────────────────────────────────────────────────────────
resource "google_compute_region_instance_group_manager" "web" {
  name               = "armor-web-mig"
  region             = var.region
  base_instance_name = "armor-web"
  target_size        = 2

  version {
    instance_template = google_compute_instance_template.web.id
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.http.id
    initial_delay_sec = 180
  }
}
