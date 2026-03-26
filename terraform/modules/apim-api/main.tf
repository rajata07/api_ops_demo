# ─────────────────────────────────────────────────────────────────────────
# Shared Terraform Module: apim-api
# ─────────────────────────────────────────────────────────────────────────
# This module is the "platform team" module that enforces:
#   - Naming conventions
#   - Default policies
#   - Product + subscription structure
#   - API versioning
#
# Product teams call this module and only provide their OpenAPI spec,
# policy XML, and a few config values.
#
# In a real org, this module lives in a SEPARATE repo and is versioned
# with git tags (v1.0, v2.0). Here it's local for demo purposes.
# ─────────────────────────────────────────────────────────────────────────

# ─── API Version Set ─────────────────────────────────────────────────────
resource "azurerm_api_management_api_version_set" "this" {
  name                = "${var.api_name}-version-set"
  resource_group_name = var.resource_group_name
  api_management_name = var.apim_name
  display_name        = var.api_display_name
  versioning_scheme   = "Segment"
}

# ─── API (imported from OpenAPI spec) ────────────────────────────────────
resource "azurerm_api_management_api" "this" {
  name                = var.api_name
  resource_group_name = var.resource_group_name
  api_management_name = var.apim_name
  revision            = var.api_revision
  display_name        = var.api_display_name
  path                = var.api_path
  protocols           = ["https"]

  version_set_id = azurerm_api_management_api_version_set.this.id
  version        = var.api_version

  import {
    content_format = "openapi"
    content_value  = var.openapi_spec
  }
}

# ─── API Policy ──────────────────────────────────────────────────────────
resource "azurerm_api_management_api_policy" "this" {
  count = var.policy_xml != null ? 1 : 0

  api_name            = azurerm_api_management_api.this.name
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name

  xml_content = var.policy_xml
}

# ─── Backend ─────────────────────────────────────────────────────────────
resource "azurerm_api_management_backend" "this" {
  count = var.backend_url != null ? 1 : 0

  name                = "${var.api_name}-backend"
  resource_group_name = var.resource_group_name
  api_management_name = var.apim_name
  protocol            = "http"
  url                 = var.backend_url
}

# ─── Product ─────────────────────────────────────────────────────────────
# Every API gets a product — this is enforced by the module.
resource "azurerm_api_management_product" "this" {
  product_id            = "${var.api_name}-product"
  api_management_name   = var.apim_name
  resource_group_name   = var.resource_group_name
  display_name          = "${var.api_display_name} Product"
  subscription_required = true
  approval_required     = var.approval_required
  published             = true
}

# ─── Add API to Product ─────────────────────────────────────────────────
resource "azurerm_api_management_product_api" "this" {
  api_name            = azurerm_api_management_api.this.name
  product_id          = azurerm_api_management_product.this.product_id
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
}

# ─── Subscription ───────────────────────────────────────────────────────
resource "azurerm_api_management_subscription" "this" {
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  display_name        = "${var.api_display_name} Subscription"
  api_id              = azurerm_api_management_api.this.id
  state               = "active"
  allow_tracing       = false
}
