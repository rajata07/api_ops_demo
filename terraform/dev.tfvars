# Dev environment
environment         = "dev"
resource_group_name = "rg-apim-demo-dev"
location            = "eastus"
apim_name           = "apim-demo-dev-unique"    # CHANGE THIS — must be globally unique
publisher_email     = "admin@contoso.com"        # CHANGE THIS
publisher_name      = "Contoso Dev"
sku_name            = "BasicV2_1"                # V2 SKU — deploys in ~5 minutes (vs 30-60 min for classic Developer_1)
backend_url         = "https://httpbin.org"      # Mock backend for demo
