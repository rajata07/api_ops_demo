# Terraform APIM Deployment — Enterprise Pattern Demo

This folder demonstrates the **recommended enterprise pattern** for deploying Azure API Management using Terraform, with:

- **Shared Terraform module** — enforces naming, policies, products, and subscriptions
- **Reusable CI/CD workflow** — one pipeline template, all teams consume it
- **Environment separation** — `dev.tfvars` / `prod.tfvars` + Terraform workspaces
- **PR-based workflow** — `terraform plan` on PRs, `terraform apply` on merge
- **Local state** — for this demo (teams should use remote state in Azure Storage)

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
SUB_KEY=$(terraform output -raw orders_api_subscription_key)

# Call the API
curl -H "Ocp-Apim-Subscription-Key: $SUB_KEY" "$GATEWAY_URL/orders/v1/orders"
```

## Architecture — What's Happening

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Platform Team (builds once)                                            │
│                                                                         │
│   modules/apim-api/        →  Enforces naming, policies, products,     │
│                                subscriptions for every API              │
│                                                                         │
│   deploy-terraform.yaml    →  Reusable CI/CD workflow                  │
│                                (plan on PR, apply on merge)             │
├─────────────────────────────────────────────────────────────────────────┤
│  Product Team (per API)                                                 │
│                                                                         │
│   main.tf                  →  Calls the module (tiny file!)            │
│   api_specs/orders-api.yaml→  OpenAPI spec (source of truth)           │
│   policies/api-policy.xml  →  API policies (rate limit, CORS, etc.)    │
│   dev.tfvars / prod.tfvars →  Environment-specific config              │
│   deploy-apim-terraform.yaml→ Calls the reusable workflow              │
└─────────────────────────────────────────────────────────────────────────┘
```

**Key point for the customer**: A product team's `main.tf` is just this:

```hcl
module "orders_api" {
  source = "./modules/apim-api"       # In real org: git::https://github.com/org/modules.git//apim-api?ref=v1.0

  apim_name        = azurerm_api_management.apim.name
  resource_group   = azurerm_resource_group.rg.name
  api_name         = "orders-api"
  api_display_name = "Orders API"
  api_path         = "orders"
  openapi_spec     = file("${path.module}/api_specs/orders-api.yaml")
  policy_xml       = file("${path.module}/policies/api-policy.xml")
  backend_url      = var.backend_url
}
```

Adding a second API = duplicate the block, change 4 values. Same standards, same pipeline.

## File Structure

```
terraform/
├── main.tf                          # APIM instance + module calls (this is what teams write)
├── variables.tf                     # Input variable definitions
├── outputs.tf                       # Output values (URLs, keys)
├── dev.tfvars                       # Dev environment values
├── prod.tfvars                      # Prod environment values
├── modules/
│   └── apim-api/                    # ← Shared module (platform team owns this)
│       ├── main.tf                  #    API + version set + policy + backend + product + subscription
│       ├── variables.tf             #    Module inputs
│       └── outputs.tf               #    Module outputs (API ID, subscription keys)
├── api_specs/
│   └── orders-api.yaml              # OpenAPI spec (source of truth for API operations)
├── policies/
│   └── api-policy.xml               # API-level policy (rate limit, CORS, headers)
└── README.md                        # This file

.github/workflows/
├── deploy-terraform.yaml            # ← Reusable workflow (platform team owns this)
└── deploy-apim-terraform.yaml       # ← Caller workflow (product team writes this)
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

Two GitHub Actions workflows handle automated deployment:

| Workflow | Purpose | Trigger |
|---|---|---|
| `deploy-terraform.yaml` | **Reusable** — runs init, plan, apply for any environment | Called by other workflows |
| `deploy-apim-terraform.yaml` | **Caller** — orchestrates dev → prod deployment | Push to `main` (apply) or PR (plan only) |

### Workflow 1: `deploy-terraform.yaml` (Reusable)

This is the **shared CI/CD template** — the "platform team" workflow. It handles the Terraform lifecycle for **any** environment. In a real org, this lives in a **separate repo** (e.g. `contoso/shared-workflows`) and is versioned with git tags.

**Trigger**: `workflow_call` only — cannot be triggered directly. Other workflows call it.

**Inputs it accepts:**

| Input | Required | Default | Description |
|---|---|---|---|
| `environment` | Yes | — | Target environment name (`dev`, `prod`) — must match a GitHub Environment |
| `working_directory` | Yes | — | Path to the Terraform root module (e.g. `terraform`) |
| `tf_var_file` | Yes | — | `.tfvars` file to use (e.g. `dev.tfvars`) |
| `terraform_version` | No | `1.9.0` | Terraform version to install |
| `plan_only` | No | `false` | If `true`, runs `plan` but skips `apply` — used for PR checks |

**Steps it runs:**

```
1. Checkout code
2. Setup Terraform (install the specified version)
3. Azure Login (OIDC with service principal)
4. terraform init
5. terraform workspace select <env> (or create if it doesn't exist)
6. terraform plan -var-file=<tfvars> -out=tfplan
7. terraform apply tfplan                                ← skipped if plan_only=true
```

**Key design choices:**

- **Workspaces**: Each environment gets its own Terraform workspace, so dev and prod have separate state files even with local state
- **Plan output saved**: The plan is saved to `tfplan` file, and `apply` uses that exact plan — no surprises between plan and apply
- **Environment protection**: When `plan_only=false`, the job is linked to a GitHub Environment, so approval gates on `prod` are respected
- **Secrets via `inherit`**: Caller workflows pass secrets with `secrets: inherit` — the reusable workflow reads `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` from the environment

### Workflow 2: `deploy-apim-terraform.yaml` (Caller)

This is what a **product team** writes. It's minimal — just calls the reusable workflow with the right inputs.

**Trigger:**

| Event | Condition | What Happens |
|---|---|---|
| `pull_request` to `main` | Changes in `terraform/**` | Runs `plan` for dev AND prod (no apply) |
| `push` to `main` | Changes in `terraform/**` | Runs `apply` to dev, then prod (sequential) |

**Path filtering**: Only triggers when files in `terraform/` change. Changes to `apimartifacts/`, `openapi.yaml`, or other files don't trigger this workflow.

**Jobs:**

```
On Pull Request:
┌──────────────┐    ┌──────────────┐
│ plan-dev     │    │ plan-prod    │     ← run in parallel
│ (plan only)  │    │ (plan only)  │     ← reviewer sees both diffs
└──────────────┘    └──────────────┘

On merge to main:
┌──────────────┐    ┌──────────────┐
│ deploy-dev   │───▶│ deploy-prod  │     ← sequential (prod waits for dev)
│ (plan+apply) │    │ (plan+apply) │     ← prod requires approval if configured
└──────────────┘    └──────────────┘
```

**The caller workflow is tiny** — this is the point. Product teams don't write CI/CD logic; they just specify which environment and which tfvars file:

```yaml
jobs:
  deploy-dev:
    uses: ./.github/workflows/deploy-terraform.yaml    # In real org: contoso/shared-workflows/...@v1.0
    with:
      environment: dev
      working_directory: terraform
      tf_var_file: dev.tfvars
    secrets: inherit
```

### Required GitHub Configuration

For the workflows to run, configure these in **Settings → Environments**:

**Environments:**

| Environment | Secrets Needed |
|---|---|
| `dev` | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` |
| `prod` | Same + optionally add a **required reviewer** for approval gate |

**Repository permissions:**

- `Settings → Actions → General → Workflow permissions` → **Read and write permissions**
- The service principal needs **Contributor** role on the Azure subscription (or scoped to the resource group)

## Adding a New API

1. Create a new OpenAPI spec in `api_specs/` (e.g. `payments-api.yaml`)
2. Optionally create a policy in `policies/` (e.g. `payments-policy.xml`)
3. Add a module block in `main.tf`:

```hcl
module "payments_api" {
  source = "./modules/apim-api"

  apim_name        = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  api_name         = "payments-api"
  api_display_name = "Payments API"
  api_path         = "payments"
  openapi_spec     = file("${path.module}/api_specs/payments-api.yaml")
  policy_xml       = file("${path.module}/policies/payments-policy.xml")
  backend_url      = var.payments_backend_url
}
```

4. Run `terraform plan` → `terraform apply`. Done. Same naming, same product, same subscription structure.

## State Management

This demo uses **local state** (`terraform.tfstate` file on disk). This is fine for a single developer.

**For teams**, use a remote backend in Azure Storage:

```hcl
backend "azurerm" {
  resource_group_name  = "rg-terraform-state"
  storage_account_name = "tfstateapim"
  container_name       = "tfstate"
  key                  = "apim-dev.tfstate"
}
```

Benefits of remote state:
- State is shared across the team
- State locking prevents concurrent `apply` conflicts
- State is backed up and versioned
- CI/CD pipelines can access it

## What the Shared Module Enforces

The `modules/apim-api/` module guarantees that **every API** deployed by any team gets:

| Standard | How It's Enforced |
|---|---|
| **Naming convention** | `api_name` must be lowercase alphanumeric with hyphens (validated) |
| **API versioning** | Version set + version are always created |
| **HTTPS only** | `protocols = ["https"]` hardcoded in module |
| **Product per API** | Product is always created and API is always linked |
| **Subscription required** | `subscription_required = true` hardcoded |
| **Active subscription** | Subscription is automatically created in `active` state |
| **Policies** | Optional but encouraged — pass `policy_xml` to apply |

Teams **cannot skip** these standards because the module creates them automatically.

## Troubleshooting

| Issue | Solution |
|---|---|
| `apim_name` already taken | APIM names are globally unique — add a random suffix |
| Deployment takes 30+ minutes | Normal for Developer SKU. Use `Consumption_0` for faster demo (but fewer features) |
| `terraform plan` shows unexpected changes | Someone modified APIM in the portal. Apply to sync back to code |
| Authentication error | Run `az login` and ensure your account has Contributor role on the subscription |
