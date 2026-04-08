variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string
}

variable "region" {
  description = "배포 리전"
  type        = string
  default     = "asia-northeast3" # 서울
}

variable "litellm_master_key" {
  description = "LiteLLM 마스터 키 (Bearer 토큰으로 사용)"
  type        = string
  sensitive   = true
}

variable "anthropic_api_key" {
  description = "Anthropic API 키 (미사용 시 빈 문자열)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "openai_api_key" {
  description = "OpenAI API 키 (미사용 시 빈 문자열)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "allow_public_access" {
  description = "Cloud Run 공개 접근 허용 (demo 목적)"
  type        = bool
  default     = false
}
