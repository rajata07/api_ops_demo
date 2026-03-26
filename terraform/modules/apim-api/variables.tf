# ─── Required Variables ───────────────────────────────────────────────────

variable "apim_name" {
  description = "Name of the existing API Management instance"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group containing the APIM instance"
  type        = string
}

variable "api_name" {
  description = "Internal name/ID for the API (used in URLs and resource names)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.api_name))
    error_message = "api_name must be lowercase alphanumeric with hyphens only."
  }
}

variable "api_display_name" {
  description = "Human-readable display name for the API"
  type        = string
}

variable "api_path" {
  description = "URL path prefix for the API (e.g. 'orders' → /orders/...)"
  type        = string
}

variable "openapi_spec" {
  description = "OpenAPI spec content (use file() to load from YAML/JSON)"
  type        = string
}

# ─── Optional Variables ───────────────────────────────────────────────────

variable "api_version" {
  description = "API version string (e.g. 'v1')"
  type        = string
  default     = "v1"
}

variable "api_revision" {
  description = "API revision number"
  type        = string
  default     = "1"
}

variable "policy_xml" {
  description = "XML policy content (use file() to load). Set to null to skip."
  type        = string
  default     = null
}

variable "backend_url" {
  description = "Backend URL for the API. Set to null to skip backend creation."
  type        = string
  default     = null
}

variable "approval_required" {
  description = "Whether product subscription requires approval"
  type        = bool
  default     = false
}
