# ============================================================
# [04] GCS Bucket (VPC-SC 경계 안의 보호 대상)
# ============================================================
# 이 버킷은 VPC-SC 경계 안에 위치
# → 경계 밖에서 접근 시 403 반환
# → 경계 안에서 PSC endpoint 통해 접근 시 성공
#
# Console 확인: Cloud Storage > Buckets
# ============================================================

data "google_project" "project" {
  project_id = var.project_id
}

resource "google_storage_bucket" "test" {
  name                        = "${var.project_id}-psc-vpcsc-test"
  location                    = "US"
  force_destroy               = true
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
}

# 테스트용 파일 업로드
resource "google_storage_bucket_object" "test_file" {
  name    = "hello.txt"
  bucket  = google_storage_bucket.test.name
  content = "Hello from inside VPC-SC perimeter!"
}
