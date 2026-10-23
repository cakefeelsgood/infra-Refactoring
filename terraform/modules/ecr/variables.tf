variable "repositories" {
  description = "생성할 ECR Repository 목록."
  type = map(object({
    name        = string
    description = string
  }))
}

variable "image_tag_mutability" {
  description = "ECR image tag mutability 설정. MUTABLE 또는 IMMUTABLE."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability 값은 MUTABLE 또는 IMMUTABLE 이어야 합니다."
  }
}

variable "scan_on_push" {
  description = "이미지 push 시 취약점 스캔 활성화 여부."
  type        = bool
  default     = true
}

variable "encryption_type" {
  description = "ECR Repository 암호화 방식. AES256 또는 KMS."
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type 값은 AES256 또는 KMS 이어야 합니다."
  }
}

variable "tags" {
  description = "공통 태그."
  type        = map(string)
  default     = {}
}