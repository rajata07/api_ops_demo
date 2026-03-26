variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "apim_name" {
  description = "Name of the API Management instance (must be globally unique)"
  type        = string
}

variable "publisher_email" {
  description = "Email address of the APIM publisher (shown in developer portal)"
  type        = string
}

variable "publisher_name" {
  description = "Name of the APIM publisher organization"
  type        = string
}

variable "sku_name" {
  description = "APIM SKU. Use 'Developer_1' for demo, 'Consumption_0' for serverless, 'Standard_1' for production"
  type        = string
  default     = "Developer_1"
}

variable "backend_url" {
  description = "Backend API URL that APIM will forward requests to"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}
