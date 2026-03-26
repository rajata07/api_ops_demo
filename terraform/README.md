# Terraform APIM Deployment — Demo Guide

This folder contains a complete Terraform setup to deploy Azure API Management instances (dev & prod) with a sample Orders API.

## What Gets Deployed

| Resource | Description |
|---|---|
| Resource Group | `rg-apim-demo-{env}` |
| API Management | APIM instance with Developer SKU |
| API | Orders API imported from OpenAPI spec |
| API Version Set | Versioned API (v1) with URL segment scheme |
| API Policy | Rate limiting + CORS + header stripping |
| Backend | Backend service pointing to your API |
| Product | "Orders API Product" with subscription required |
| Product-API link | Associates the Orders API with the product |
| Subscription | Active subscription key scoped to the API |
| Named Value | Stores the backend URL as a config value |

## Prerequisites

1. **Terraform** >= 1.5.0 — [Install guide](https://developer.hashicorp.com/terraform/install)
2. **Azure CLI** — [Install guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
3. An **Azure subscription** with permissions to create resources

## Quick Start

### 1. Login to Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 2. Update the `.tfvars` files

Edit `dev.tfvars` and `prod.tfvars` — at minimum change:

- `apim_name` — must be **globally unique** across all of Azure
- `publisher_email` — your email address

### 3. Deploy Dev

```bash
cd terraform

# Initialize Terraform (downloads providers)
terraform init

# Preview what will be created
terraform plan -var-file=dev.tfvars

# Deploy
terraform apply -var-file=dev.tfvars
```

> **Note**: APIM provisioning takes **30-60 minutes** for Developer SKU. This is an Azure limitation, not Terraform.

### 4. Deploy Prod

Since dev and prod use different state, you can use [Terraform workspaces](https://developer.hashicorp.com/terraform/language/state/workspaces) to manage them:

```bash
# Create and switch to prod workspace
terraform workspace new prod

# Deploy prod
terraform apply -var-file=prod.tfvars
```

Or if you prefer separate state directories:

```bash
# From a separate terminal/directory, or use -chdir
terraform init
terraform apply -var-file=prod.tfvars
```

### 5. Verify Deployment

After `terraform apply` completes:

```bash
# See all outputs
terraform output

# Get the API gateway URL
terraform output apim_gateway_url

# Get the subscription key (sensitive)
terraform output -raw subscription_primary_key
```

### 6. Test the API

```bash
# Get the values
GATEWAY_URL=$(terraform output -raw apim_gateway_url)
SUB_KEY=$(terraform output -raw subscription_primary_key)

# Call the API
curl -H "Ocp-Apim-Subscription-Key: $SUB_KEY" "$GATEWAY_URL/orders/v1/orders"
```

## File Structure

```
terraform/
├── main.tf                  # All APIM resources (instance, API, policies, products, etc.)
├── variables.tf             # Input variable definitions
├── outputs.tf               # Output values (URLs, keys)
├── dev.tfvars               # Dev environment values
├── prod.tfvars              # Prod environment values
├── api_specs/
│   └── orders-api.yaml      # OpenAPI spec (source of truth for API operations)
├── policies/
│   └── api-policy.xml       # API-level policy (rate limit, CORS, headers)
└── README.md                # This file
```

## Common Operations

### Make a change to the API

1. Edit `api_specs/orders-api.yaml` (add/remove operations, update schemas)
2. Run `terraform plan -var-file=dev.tfvars` to see the diff
3. Run `terraform apply -var-file=dev.tfvars` to deploy

### Update a policy

1. Edit `policies/api-policy.xml`
2. Run `terraform apply -var-file=dev.tfvars`

### Check for drift (someone changed APIM in the portal)

```bash
terraform plan -var-file=dev.tfvars
```

If there's drift, the plan will show what changed. Apply to bring it back in sync.

### Destroy everything

```bash
# Destroy dev
terraform destroy -var-file=dev.tfvars

# Switch to prod workspace and destroy
terraform workspace select prod
terraform destroy -var-file=prod.tfvars
```

## CI/CD

For automated deployment via GitHub Actions, see the `deploy-terraform.yaml` workflow example in the root [README.md](../README.md#example-terraform-cicd-workflow).

## Troubleshooting

| Issue | Solution |
|---|---|
| `apim_name` already taken | APIM names are globally unique — add a random suffix |
| Deployment takes 30+ minutes | Normal for Developer SKU. Use `Consumption_0` for faster demo (but fewer features) |
| `terraform plan` shows unexpected changes | Someone modified APIM in the portal. Apply to sync back to code |
| Authentication error | Run `az login` and ensure your account has Contributor role on the subscription |
