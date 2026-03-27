# Prod environment
environment         = "prod"
resource_group_name = "rg-apim-demo-prod"
location            = "eastus"
apim_name           = "apim-demo-prod-unique"   # CHANGE THIS — must be globally unique
publisher_email     = "admin@contoso.com"        # CHANGE THIS
publisher_name      = "Contoso"
sku_name            = "BasicV2_1"                # V2 SKU — use "StandardV2_1" or "PremiumV2_1" for real production
backend_url         = "https://httpbin.org"      # Replace with your real backend
