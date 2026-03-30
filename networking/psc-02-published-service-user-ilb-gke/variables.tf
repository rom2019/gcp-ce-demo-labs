variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "region" {
  description = "GCP 리전"
  type        = string
  default     = "asia-northeast3"
}

# ============================================================
# Phase 2 변수 (GKE ILB 생성 후 입력)
# ============================================================
# GKE 가 K8s Service(LoadBalancer/Internal) 를 감지하면
# 자동으로 forwarding rule 을 생성하는데, 이름이 a<hash> 형태로 자동 생성됨
#
# Phase 1 apply 후 아래 명령어로 이름 확인:
#   gcloud compute forwarding-rules list \
#     --regions=<region> \
#     --project=<project_id> \
#     --filter="loadBalancingScheme=INTERNAL"
#
# 확인 후 terraform.tfvars 에 추가:
#   ilb_forwarding_rule_name = "a1b2c3d4e5f6..."
# ============================================================
variable "ilb_forwarding_rule_name" {
  description = "GKE 가 생성한 L4 ILB forwarding rule 이름 (Phase 1 apply 후 gcloud 로 확인)"
  type        = string
  default     = ""
}
