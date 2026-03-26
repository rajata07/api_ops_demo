terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # ─── Local State (for demo) ────────────────────────────────────────────
  # State is stored locally in terraform.tfstate
  # For teams: use a remote backend (Azure Storage) to share state & enable locking
  #
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "tfstateapim"
  #   container_name       = "tfstate"
  #   key                  = "apim-dev.tfstate"    # use apim-prod.tfstate for prod
  # }
}

provider "azurerm" {
  features {}
}

# ─── Resource Group ──────────────────────────────────────────────────────
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# ─── APIM Instance ──────────────────────────────────────────────────────
resource "azurerm_api_management" "apim" {
  name                = var.apim_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  publisher_email     = var.publisher_email
  publisher_name      = var.publisher_name
  sku_name            = var.sku_name

  tags = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# ─────────────────────────────────────────────────────────────────────────
# API Deployments — each API calls the shared module
# ─────────────────────────────────────────────────────────────────────────
# The module enforces: naming conventions, versioning, product creation,
# subscription, and optional policies/backends.
#
# In a real org, the module source would be a remote git repo with a tag:
#   source = "git::https://github.com/contoso/terraform-modules.git//modules/apim-api?ref=v1.0"
#
# Here we use a local path for demo purposes.
# ─────────────────────────────────────────────────────────────────────────

module "orders_api" {
  source = "./modules/apim-api"

  apim_name           = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  api_name            = "orders-api"
  api_display_name    = "Orders API"
  api_path            = "orders"
  api_version         = "v1"
  openapi_spec        = file("${path.module}/api_specs/orders-api.yaml")
  policy_xml          = file("${path.module}/policies/api-policy.xml")
  backend_url         = var.backend_url
}

# ─────────────────────────────────────────────────────────────────────────
# Adding a second API? Just add another module block:
# ─────────────────────────────────────────────────────────────────────────
#
# module "payments_api" {
#   source = "./modules/apim-api"
#
#   apim_name           = azurerm_api_management.apim.name
#   resource_group_name = azurerm_resource_group.rg.name
#   api_name            = "payments-api"
#   api_display_name    = "Payments API"
#   api_path            = "payments"
#   api_version         = "v1"
#   openapi_spec        = file("${path.module}/api_specs/payments-api.yaml")
#   policy_xml          = file("${path.module}/policies/payments-policy.xml")
#   backend_url         = var.payments_backend_url
# }

# ─── Named Value ─────────────────────────────────────────────────────────
resource "azurerm_api_management_named_value" "backend_url" {
  name                = "backend-url"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  display_name        = "backend-url"
  value               = var.backend_url
  secret              = false
}
