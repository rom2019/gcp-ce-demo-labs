# 07_compute.tf

locals {
  # 공통 startup script 앞부분 (패키지 업데이트)
  base_script = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y curl wget
  EOF
}

# ── 공통 서비스 계정 ───────────────────────────────────
# 각 VM 그룹마다 최소 권한 서비스 계정 분리
resource "google_service_account" "bastion" {
  account_id   = "sa-bastion"
  display_name = "Bastion Host Service Account"
}

resource "google_service_account" "web" {
  account_id   = "sa-web"
  display_name = "Web Frontend Service Account"
}

resource "google_service_account" "app" {
  account_id   = "sa-app"
  display_name = "App Backend Service Account"
}

resource "google_service_account" "analytics" {
  account_id   = "sa-analytics"
  display_name = "Analytics Service Account"
}

# Analytics VM 은 BigQuery 쓰기 권한 필요
resource "google_project_iam_member" "analytics_bq" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.analytics.email}"
}

# ── Bastion Host ───────────────────────────────────────
# IAP SSH 로만 접근 / 공인 IP 없음
resource "google_compute_instance" "bastion" {
  name         = "bastion-host"
  machine_type = "e2-micro"
  zone         = var.zone

  tags = ["bastion"] # IAP SSH 방화벽 규칙 적용

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id
    # access_config 없음 = 공인 IP 없음
  }

  service_account {
    email  = google_service_account.bastion.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE" # IAP 접속용
  }
}

# ── Web Instance Template (Nginx) ──────────────────────
resource "google_compute_instance_template" "web" {
  name_prefix  = "web-template-"
  machine_type = "e2-micro"

  tags = ["frontend-vm"] # LB → Frontend 방화벽 규칙 적용

  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
    disk_size_gb = 10
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id
    # access_config 없음 = 공인 IP 없음
  }

  service_account {
    email  = google_service_account.web.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = <<-EOF
      #!/bin/bash
      apt-get update -y
      apt-get install -y nginx
      # 어느 VM 인지 확인용 페이지
      echo "<h1>Frontend VM: $(hostname)</h1>" > /var/www/html/index.html
      systemctl enable nginx
      systemctl start nginx
    EOF
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Web MIG ────────────────────────────────────────────
resource "google_compute_instance_group_manager" "web" {
  name               = "mig-web"
  base_instance_name = "web"
  zone               = var.zone

  version {
    instance_template = google_compute_instance_template.web.id
  }

  target_size = 2 # VM 2대

  named_port {
    name = "http"
    port = 80
  }
}

# ── App Instance Template (Python) ────────────────────
resource "google_compute_instance_template" "app" {
  name_prefix  = "app-template-"
  machine_type = "e2-micro"

  tags = ["app-vm"] # Frontend → App 방화벽 규칙 적용

  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
    disk_size_gb = 10
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    # access_config 없음 = 공인 IP 없음
  }

  service_account {
    email  = google_service_account.app.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y python3 python3-pip python3-venv

    # 가상환경 생성
    python3 -m venv /opt/venv
    source /opt/venv/bin/activate

    # 패키지 설치
    pip install fastapi uvicorn psycopg2-binary redis

    # app.py 생성
    cat > /opt/app.py << 'PYEOF'
  from fastapi import FastAPI
  app = FastAPI()

  @app.get("/health")
  def health():
      return {"status": "ok", "host": __import__("socket").gethostname()}

  @app.get("/")
  def root():
      return {"message": "App VM", "host": __import__("socket").gethostname()}
  PYEOF

    # 서비스 등록
    cat > /etc/systemd/system/app.service << 'SVCEOF'
  [Unit]
  Description=FastAPI App
  After=network.target

  [Service]
  ExecStart=/opt/venv/bin/uvicorn app:app --host 0.0.0.0 --port 8080 --app-dir /opt
  Restart=always
  User=root

  [Install]
  WantedBy=multi-user.target
  SVCEOF

    systemctl daemon-reload
    systemctl enable app
    systemctl start app
  EOF
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── App MIG ────────────────────────────────────────────
resource "google_compute_instance_group_manager" "app" {
  name               = "mig-app"
  base_instance_name = "app"
  zone               = var.zone

  version {
    instance_template = google_compute_instance_template.app.id
  }

  target_size = 2 # VM 2대

  named_port {
    name = "http"
    port = 8080
  }
}

# ── Analytics VM ───────────────────────────────────────
resource "google_compute_instance" "analytics" {
  name         = "analytics-vm"
  machine_type = "e2-micro"
  zone         = var.zone

  tags = ["analytics-vm"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.data.id
    # access_config 없음 = 공인 IP 없음
  }

  service_account {
    email  = google_service_account.analytics.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = <<-EOF
      #!/bin/bash
      apt-get update -y
      apt-get install -y python3 python3-pip
      pip3 install google-cloud-bigquery
    EOF
  }
}