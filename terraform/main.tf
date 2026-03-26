terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Uncomment and configure for remote state storage (recommended for teams)
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "tfstateapim"
  #   container_name       = "tfstate"
  #   key                  = "apim.tfstate"
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

# ─── API Management Instance ────────────────────────────────────────────
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

# ─── API Version Set (for versioned APIs) ────────────────────────────────
resource "azurerm_api_management_api_version_set" "orders_version_set" {
  name                = "orders-api-version-set"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  display_name        = "Orders API"
  versioning_scheme   = "Segment" # version in URL path: /orders/v1/...
}

# ─── API (imported from OpenAPI spec file) ───────────────────────────────
# The OpenAPI YAML file is the source of truth for all operations/schemas.
# Terraform does NOT define operations — the spec file does.
resource "azurerm_api_management_api" "orders" {
  name                = "orders-api"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "Orders API"
  path                = "orders"
  protocols           = ["https"]

  # Versioning (optional — remove version_set_id and version if not needed)
  version_set_id = azurerm_api_management_api_version_set.orders_version_set.id
  version        = "v1"

  import {
    content_format = "openapi"
    content_value  = file("${path.module}/api_specs/orders-api.yaml")
  }
}

# ─── API Policy ──────────────────────────────────────────────────────────
resource "azurerm_api_management_api_policy" "orders_policy" {
  api_name            = azurerm_api_management_api.orders.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name

  xml_content = file("${path.module}/policies/api-policy.xml")
}

# ─── Backend ─────────────────────────────────────────────────────────────
resource "azurerm_api_management_backend" "orders_backend" {
  name                = "orders-backend"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  protocol            = "http"
  url                 = var.backend_url
}

# ─── Product ─────────────────────────────────────────────────────────────
# A product groups APIs and controls access via subscriptions.
resource "azurerm_api_management_product" "orders_product" {
  product_id            = "orders-product"
  api_management_name   = azurerm_api_management.apim.name
  resource_group_name   = azurerm_resource_group.rg.name
  display_name          = "Orders API Product"
  subscription_required = true
  approval_required     = false
  published             = true # makes it visible in the developer portal
}

# ─── Add API to Product ─────────────────────────────────────────────────
resource "azurerm_api_management_product_api" "orders_product_api" {
  api_name            = azurerm_api_management_api.orders.name
  product_id          = azurerm_api_management_product.orders_product.product_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
}

# ─── Subscription ───────────────────────────────────────────────────────
# Creates a subscription key scoped to this specific API.
resource "azurerm_api_management_subscription" "orders_subscription" {
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  display_name        = "Orders API Subscription"
  api_id              = azurerm_api_management_api.orders.id
  state               = "active"
  allow_tracing       = false
}

# ─── Named Value ─────────────────────────────────────────────────────────
resource "azurerm_api_management_named_value" "backend_url" {
  name                = "backend-url"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  display_name        = "backend-url"
  value               = var.backend_url
  secret              = false
}
