output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.rg.name
}

output "apim_name" {
  description = "Name of the API Management instance"
  value       = azurerm_api_management.apim.name
}

output "apim_gateway_url" {
  description = "Gateway URL of the APIM instance"
  value       = azurerm_api_management.apim.gateway_url
}

output "apim_developer_portal_url" {
  description = "Developer portal URL"
  value       = azurerm_api_management.apim.developer_portal_url
}

output "api_url" {
  description = "Full URL to the Orders API"
  value       = "${azurerm_api_management.apim.gateway_url}/orders/v1"
}

output "subscription_primary_key" {
  description = "Primary subscription key for the Orders API"
  value       = azurerm_api_management_subscription.orders_subscription.primary_key
  sensitive   = true
}
