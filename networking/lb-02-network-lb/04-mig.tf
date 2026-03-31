# ────────────────────────────────────────────────────────────────────
# Regional Managed Instance Group (MIG)
# ────────────────────────────────────────────────────────────────────
resource "google_compute_region_instance_group_manager" "game" {
  name               = "game-mig"
  region             = var.region
  base_instance_name = "game"
  target_size        = 2

  version {
    instance_template = google_compute_instance_template.game.id
  }

  # NLB(Passthrough)는 named_port 불필요 — L4 레벨 포트 직접 전달
  auto_healing_policies {
    health_check      = google_compute_region_health_check.tcp.id
    initial_delay_sec = 180
  }
}

# ────────────────────────────────────────────────────────────────────
# Auto Scaler
# ────────────────────────────────────────────────────────────────────
resource "google_compute_region_autoscaler" "game" {
  name   = "game-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.game.id

  autoscaling_policy {
    min_replicas    = 2
    max_replicas    = 10
    cooldown_period = 60

    cpu_utilization {
      target = 0.7
    }
  }
}
