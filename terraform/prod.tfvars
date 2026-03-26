# Prod environment
environment         = "prod"
resource_group_name = "rg-apim-demo-prod"
location            = "eastus"
apim_name           = "apim-demo-prod-unique"   # CHANGE THIS — must be globally unique
publisher_email     = "admin@contoso.com"        # CHANGE THIS
publisher_name      = "Contoso"
sku_name            = "Developer_1"              # Use "Standard_1" or "Premium_1" for real production
backend_url         = "https://httpbin.org"      # Replace with your real backend
