output "api_id" {
  description = "Resource ID of the API"
  value       = azurerm_api_management_api.this.id
}

output "api_name" {
  description = "Name of the API"
  value       = azurerm_api_management_api.this.name
}

output "product_id" {
  description = "Product ID associated with this API"
  value       = azurerm_api_management_product.this.product_id
}

output "subscription_primary_key" {
  description = "Primary subscription key"
  value       = azurerm_api_management_subscription.this.primary_key
  sensitive   = true
}

output "subscription_secondary_key" {
  description = "Secondary subscription key"
  value       = azurerm_api_management_subscription.this.secondary_key
  sensitive   = true
}
