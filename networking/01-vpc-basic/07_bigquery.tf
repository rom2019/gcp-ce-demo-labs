# 06_bigquery.tf

# ── BigQuery 데이터셋 ──────────────────────────────────
resource "google_bigquery_dataset" "main" {
  dataset_id  = "network_lab"
  description = "GCP 네트워크 실습용 데이터셋"
  location    = "US"

  # terraform destroy 시 테이블/데이터 포함 삭제 (학습용)
  # 프로덕션에서는 false 로 설정해서 실수로 날리는 것 방지
  delete_contents_on_destroy = true

  # 접근 제어 주의사항:
  # 현재는 프로젝트 기본 IAM 으로만 제어
  # 프로덕션에서는 VPC Service Controls 로 추가 제한 권장  
}

# ── 테이블: 웹 접근 로그 ───────────────────────────────
resource "google_bigquery_table" "access_log" {
  dataset_id          = google_bigquery_dataset.main.dataset_id
  table_id            = "access_log"
  deletion_protection = false

  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "client_ip"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "method"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "path"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "status_code"
      type = "INTEGER"
      mode = "REQUIRED"
    },
    {
      name = "response_time_ms"
      type = "INTEGER"
      mode = "NULLABLE"
    }
  ])
}

# ── 테이블: VPC Flow Logs ──────────────────────────────
# 나중에 VPC Flow Logs → BigQuery 실습 때 사용
resource "google_bigquery_table" "vpc_flow_logs" {
  dataset_id          = google_bigquery_dataset.main.dataset_id
  table_id            = "vpc_flow_logs"
  deletion_protection = false

  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "src_ip"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "dst_ip"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "src_port"
      type = "INTEGER"
      mode = "NULLABLE"
    },
    {
      name = "dst_port"
      type = "INTEGER"
      mode = "NULLABLE"
    },
    {
      name = "protocol"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "bytes_sent"
      type = "INTEGER"
      mode = "NULLABLE"
    }
  ])
}