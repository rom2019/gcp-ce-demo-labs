# ============================================================
# [05] VPC Service Controls
# ============================================================
# 구성 요소 3가지:
#
#   1. Access Policy  — 조직 레벨의 VPC-SC 정책 컨테이너
#   2. Access Level   — "경계 안" 으로 인정하는 조건 정의
#                       (이 예제: Test VM 의 Service Account)
#   3. Service Perimeter — 보호할 리소스/서비스 범위 정의
#                          (이 예제: storage.googleapis.com in this project)
#
# 흐름:
#   외부 요청 → VPC-SC 검사 → Access Level 미충족 → 403
#   VM (SA) → PSC endpoint → VPC-SC 검사 → Access Level 충족 → 200
#
# Console 확인: Security > VPC Service Controls
# ============================================================

# 1. Access Policy (조직 레벨 컨테이너)
# scopes 로 이 프로젝트에만 적용되는 scoped policy 생성
# → 조직의 기존 policy 와 충돌 없음
resource "google_access_context_manager_access_policy" "policy" {
  parent = "organizations/${var.org_id}"
  title  = "psc-03b-demo-policy"
  scopes = ["projects/${data.google_project.project.number}"]
}

# 2. Access Level — Test VM SA 만 경계 안으로 허용
# members 에 포함된 identity 는 VPC-SC 경계를 통과할 수 있음
resource "google_access_context_manager_access_level" "vm_access" {
  parent = "accessPolicies/${google_access_context_manager_access_policy.policy.name}"
  name   = "accessPolicies/${google_access_context_manager_access_policy.policy.name}/accessLevels/pscVmAccess"
  title  = "psc-vm-access"

  basic {
    conditions {
      members = [
        "serviceAccount:${google_service_account.test_vm.email}",
      ]
    }
  }
}

# 3. Service Perimeter — storage.googleapis.com 보호
resource "google_access_context_manager_service_perimeter" "perimeter" {
  parent = "accessPolicies/${google_access_context_manager_access_policy.policy.name}"
  name   = "accessPolicies/${google_access_context_manager_access_policy.policy.name}/servicePerimeters/pscPerimeter"
  title  = "psc-perimeter"

  status {
    # 보호할 서비스
    restricted_services = ["storage.googleapis.com"]

    # 보호 범위: 이 프로젝트
    resources = ["projects/${data.google_project.project.number}"]

    # 이 Access Level 을 만족하는 identity 는 접근 허용
    access_levels = [google_access_context_manager_access_level.vm_access.name]
  }

  depends_on = [google_access_context_manager_access_level.vm_access]
}
