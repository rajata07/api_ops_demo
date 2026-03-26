# APIOps Demo - Azure API Management CI/CD

This repository implements [APIOps](https://github.com/Azure/APIOps) for Azure API Management (APIM). APIOps applies GitOps principles to API deployment — your APIM configuration is stored as code in this repository and automatically synchronized to Azure through CI/CD pipelines.

## Table of Contents

- [Repository Structure](#repository-structure)
- [How It Works — End-to-End Flow](#how-it-works--end-to-end-flow)
- [Workflows](#workflows)
  - [1. Run - Extractor (`run-extractor.yaml`)](#1-run---extractor-run-extractoryaml)
  - [2. Run - Publisher (`run-publisher.yaml`)](#2-run---publisher-run-publisheryaml)
  - [3. Run Publisher with Environment (`run-publisher-with-env.yaml`)](#3-run-publisher-with-environment-run-publisher-with-envyaml)
- [Configuration Files](#configuration-files)
  - [Extractor Configuration (`configuration.extractor.yaml`)](#extractor-configuration-configurationextractoryaml)
  - [Environment Configuration (`configuration.prod.yaml`)](#environment-configuration-configurationprodyaml)
- [API Specification Formats](#api-specification-formats)
- [What is `apiops_release_version`?](#what-is-apiops_release_version)
- [GitHub Secrets and Environments](#github-secrets-and-environments)
- [Deployment Flow: Dev to Prod](#deployment-flow-dev-to-prod)
- [APIM CI/CD Approaches: APIOps vs OpenAPI-in-Code](#apim-cicd-approaches-apiops-vs-openapi-in-code)
  - [Approach 1: APIOps Extractor/Publisher](#approach-1-apiops-extractorpublisher)
  - [Approach 2: OpenAPI Spec in Code + Direct Deploy](#approach-2-openapi-spec-in-code--direct-deploy)
  - [Which One Should You Use?](#which-one-should-you-use)
- [Terraform for APIM CI/CD](#terraform-for-apim-cicd)
  - [Can Terraform Replace the APIOps Extractor/Publisher?](#can-terraform-replace-the-apiops-extractorpublisher)
  - [How Terraform Works for APIM](#how-terraform-works-for-apim)
  - [Defining APIs in Terraform: Import from File vs Inline](#defining-apis-in-terraform-import-from-file-vs-inline)
  - [Example: Full APIM Management with Terraform](#example-full-apim-management-with-terraform)
  - [Example: Terraform CI/CD Workflow](#example-terraform-cicd-workflow)
  - [Terraform vs APIOps: Side-by-Side](#terraform-vs-apiops-side-by-side)
- [References](#references)

---

## Repository Structure

```
.
├── .github/workflows/
│   ├── run-extractor.yaml              # Extracts APIM config from Azure → Git
│   ├── run-publisher.yaml              # Orchestrates publishing from Git → Azure
│   └── run-publisher-with-env.yaml     # Reusable workflow called by run-publisher.yaml
├── apimartifacts/                      # Extracted APIM artifacts (APIs, policies, backends, etc.)
├── configuration.extractor.yaml        # Controls which resources the extractor pulls
├── configuration.prod.yaml             # Environment-specific overrides for production
└── README.md
```

### `apimartifacts/` Directory

This folder contains the APIM artifacts extracted from your Azure APIM instance. It includes APIs, policies, diagnostics, loggers, named values, products, subscriptions, and groups. **Do not manually edit files here unless you know what you are doing** — this folder is populated by the extractor pipeline and consumed by the publisher pipeline.

---

## How It Works — End-to-End Flow

APIOps uses two tools — the **Extractor** and the **Publisher** — to manage the lifecycle of your API configurations:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        APIOps Workflow                               │
│                                                                     │
│  1. EXTRACT (manual trigger)                                        │
│     Azure APIM (Dev) ──→ Extractor ──→ Pull Request with artifacts  │
│                                                                     │
│  2. REVIEW & MERGE                                                  │
│     Developer reviews PR ──→ Merges to main                         │
│                                                                     │
│  3. PUBLISH (automatic on merge to main)                            │
│     main branch ──→ Publisher ──→ Dev APIM ──→ Prod APIM            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Step-by-step:**

1. **Extract**: A developer manually triggers the extractor workflow. It connects to the source (dev) APIM instance, pulls down the current configuration, and creates a **Pull Request** with the artifacts.
2. **Review**: The team reviews the PR. You can make changes to APIs, policies, or configurations directly in the PR before merging.
3. **Merge**: Once the PR is merged into `main`, the publisher workflow **automatically triggers**.
4. **Publish to Dev**: The publisher first deploys changes to the **dev** APIM instance.
5. **Publish to Prod**: After the dev deployment succeeds, the publisher promotes the changes to **prod** (requires environment approval if configured).

> **Important**: The publisher pipeline is **not** automatically triggered by the extractor. The extractor only creates a PR. The publisher triggers when that PR (or any other change) is **merged to `main`**.

---

## Workflows

### 1. Run - Extractor (`run-extractor.yaml`)

**Purpose**: Extracts the current APIM configuration from Azure and creates a Pull Request with the artifacts in this repository.

| Property | Value |
|---|---|
| **Trigger** | Manual only (`workflow_dispatch`) |
| **Environment** | `dev` |
| **Output** | A Pull Request containing extracted artifacts in `apimartifacts/` |

**How to run it:**

1. Go to **Actions** → **Run - Extractor**
2. Click **Run workflow**
3. Choose your inputs:

| Input | Description |
|---|---|
| `CONFIGURATION_YAML_PATH` | Choose **"Extract All APIs"** to extract everything, or **"configuration.extractor.yaml"** to extract only the resources listed in the config file |
| `API_SPECIFICATION_FORMAT` | The format for extracted API specifications (see [API Specification Formats](#api-specification-formats)) |

**What it does:**

1. Checks out the repository
2. Downloads the APIOps extractor tool from the [Azure/APIOps](https://github.com/Azure/APIOps) releases
3. Connects to your APIM instance using the service principal credentials stored in GitHub secrets
4. Extracts APIM artifacts (APIs, policies, named values, backends, loggers, etc.) into the `apimartifacts/` folder
5. Uploads the artifacts as a GitHub Actions artifact
6. Creates a **Pull Request** with the changes for review

**Example**: If you have made changes to APIs directly in the Azure Portal and want to sync those changes back into Git, run the extractor.

---

### 2. Run - Publisher (`run-publisher.yaml`)

**Purpose**: Orchestrates the deployment of APIM artifacts from this repository to Azure APIM instances (dev, then prod).

| Property | Value |
|---|---|
| **Trigger** | Automatic on push to `main` **+ Manual** (`workflow_dispatch`) |
| **Environments** | `dev` → `prod` (sequential) |

**Automatic trigger**: Any push to the `main` branch (including merged PRs from the extractor) automatically triggers this workflow.

**Manual trigger**: Go to **Actions** → **Run - Publisher** → **Run workflow** and choose:

| Input | Options | Description |
|---|---|---|
| `COMMIT_ID_CHOICE` | `publish-artifacts-in-last-commit` (default) | Only publishes artifacts that changed in the last commit |
| | `publish-all-artifacts-in-repo` | Force-publishes all artifacts in `apimartifacts/` — useful after a build failure or to ensure everything is in sync |

**What it does:**

This workflow calls the reusable `run-publisher-with-env.yaml` workflow for each environment. The deployment jobs are structured as follows:

```
get-commit
    │
    ├── Push-Changes-To-APIM-Dev      (always runs first)
    │       │
    │       └── Push-Changes-To-APIM-Prod   (runs after dev succeeds)
    │
    └── (or if "publish-all-artifacts-in-repo" was chosen, a separate path without commit ID)
```

**Key behavior:**
- **Dev deployment** does **not** use a configuration YAML — it publishes artifacts as-is
- **Prod deployment** uses `configuration.prod.yaml` to apply environment-specific overrides (e.g., different backend URLs, service names, named values)
- **Prod waits for Dev** — the prod job has a `needs` dependency on the dev job, so it only runs after dev succeeds
- If you have configured [environment protection rules](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment#deployment-protection-rules) on the `prod` environment in GitHub, you will be prompted to approve the deployment before it proceeds to prod

---

### 3. Run Publisher with Environment (`run-publisher-with-env.yaml`)

**Purpose**: A **reusable workflow** (called by `run-publisher.yaml`) that performs the actual publishing to a specific APIM environment.

| Property | Value |
|---|---|
| **Trigger** | `workflow_call` only (cannot be triggered directly) |
| **Called by** | `run-publisher.yaml` |

**Inputs it accepts:**

| Input | Required | Description |
|---|---|---|
| `API_MANAGEMENT_ENVIRONMENT` | Yes | Target environment name (e.g., `dev`, `prod`) — must match a GitHub Environment |
| `CONFIGURATION_YAML_PATH` | No | Path to the environment config YAML (e.g., `configuration.prod.yaml`). If empty, no overrides are applied |
| `COMMIT_ID` | No | If provided, only changed artifacts are published. If empty, all artifacts are published |
| `API_MANAGEMENT_SERVICE_OUTPUT_FOLDER_PATH` | Yes | Path to the artifacts folder (`apimartifacts`) |

**What it does:**

1. Checks out the repository
2. Runs [Spectral](https://stoplight.io/open-source/spectral) API linting on the extracted API specs
3. Performs **secret token substitution** in `configuration.{env}.yaml` — replaces `{#tokenName#}` placeholders with actual secret values from GitHub Secrets
4. Downloads the APIOps publisher tool
5. Publishes artifacts to the target APIM instance

The workflow has four conditional steps to handle all combinations:

| Condition | Behavior |
|---|---|
| No config YAML + has commit ID | Publishes only changed artifacts, no overrides |
| No config YAML + no commit ID | Publishes all artifacts, no overrides |
| Has config YAML + has commit ID | Publishes only changed artifacts with overrides |
| Has config YAML + no commit ID | Publishes all artifacts with overrides |

---

## Configuration Files

### Extractor Configuration (`configuration.extractor.yaml`)

Controls **which** APIM resources the extractor should pull. If you select "Extract All APIs" when running the extractor, this file is ignored and everything is extracted.

```yaml
apiNames:                    # Which APIs to extract
  - mock-api-operation

backendNames:                # Which backends to extract (empty = none)

diagnosticNames:             # Which diagnostic settings to extract
  - applicationinsights
  - azuremonitor

loggerNames:                 # Which loggers to extract
  - azuremonitor
  - app-insights

namedValueNames:             # Which named values to extract
  - 69b40de47b201b1da8d5d6a9

productNames:                # Which products to extract
  - developers-x-team

subscriptionNames:           # Which subscriptions to extract
  - master
  - 69c040597e3c4c3fade4d551

tagNames:                    # Which tags to extract (empty = none)

policyFragmentNames:         # Which policy fragments to extract (empty = none)
```

Use this file to limit extraction to specific resources — useful when your APIM instance has many APIs and you only want to manage a subset via APIOps.

### Environment Configuration (`configuration.prod.yaml`)

Provides **overrides** when publishing to the production environment. This allows you to change values like the APIM service name, backend URLs, named values, logger configurations, etc.

```yaml
apimServiceName: contiworkshopapimprod    # Target APIM instance for prod
namedValues:                               # Override named values for prod
loggers:                                   # Override logger configs for prod
diagnostics:                               # Override diagnostic settings for prod
backends:                                  # Override backend URLs for prod
apis:                                      # Override API-level settings for prod
```

For a full example with all override options, see the [sample configuration file](https://github.com/Azure/apiops/blob/main/configuration.prod.yaml) in the APIOps repository.

**Token substitution**: If you have secrets that need to be injected at deployment time, use the `{#tokenName#}` syntax in the config file. For example:

```yaml
namedValues:
  - name: testSecret
    properties:
      displayName: testSecret
      value: "{#testSecretValue#}"
```

The publisher workflow replaces `{#testSecretValue#}` with the value of the `testSecretValue` GitHub secret at runtime.

---

## API Specification Formats

When running the extractor, you choose an API specification format. This determines how your API definitions are exported:

| Format | Description | When to Use |
|---|---|---|
| **OpenAPIV3Yaml** | OpenAPI 3.0 in YAML format | **Recommended default**. Human-readable, easy to review in PRs, widely supported by modern tools |
| **OpenAPIV3Json** | OpenAPI 3.0 in JSON format | When your toolchain requires JSON (e.g., some code generators or validators). Functionally identical to OpenAPIV3Yaml |
| **OpenAPIV2Yaml** | Swagger 2.0 in YAML format | Legacy compatibility. Use only if your downstream tools require Swagger 2.0 |
| **OpenAPIV2Json** | Swagger 2.0 in JSON format | Legacy compatibility with JSON requirement. Also known as "Swagger JSON" |

**Recommendation**: Use **OpenAPIV3Yaml** unless you have a specific reason to choose another format. OpenAPI 3.0 is the current standard and YAML is easier to read and review in pull requests compared to JSON.

> **Note**: The format only affects API specification files. Other artifacts (policies, named values, loggers, etc.) are always extracted in their native format.

---

## What is `apiops_release_version`?

```yaml
env:
  apiops_release_version: v6.0.2
```

This is the version of the [APIOps Toolkit](https://github.com/Azure/APIOps/releases) used by the workflows. Both the extractor and publisher workflows download their executable binaries from the APIOps GitHub releases using this version tag.

The download URL is constructed as:
```
https://github.com/Azure/apiops/releases/download/{version}/publisher-linux-x64.zip
https://github.com/Azure/apiops/releases/download/{version}/extractor-linux-x64.zip
```

**To update**: Change the value in **both** workflow files:
- `.github/workflows/run-extractor.yaml`
- `.github/workflows/run-publisher-with-env.yaml`

Check the [APIOps Releases](https://github.com/Azure/APIOps/releases) page for the latest version.

---

## GitHub Secrets and Environments

### Environments

You need two GitHub Environments configured under **Settings → Environments**:

| Environment | Purpose |
|---|---|
| `dev` | Source environment for extraction; first deployment target for publishing |
| `prod` | Production deployment target (optionally with approval gates) |

> **Tip**: Add a [required reviewer](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment#required-reviewers) on the `prod` environment to enforce manual approval before production deployments.

### Secrets (per environment)

Each environment needs these secrets:

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | Service principal application (client) ID |
| `AZURE_CLIENT_SECRET` | Service principal client secret |
| `AZURE_TENANT_ID` | Azure Active Directory tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID containing the APIM instance |
| `AZURE_RESOURCE_GROUP_NAME` | Resource group name where the APIM instance is deployed |
| `API_MANAGEMENT_SERVICE_NAME` | Name of the APIM service instance |

### Variables (optional)

| Variable | Description |
|---|---|
| `LOG_LEVEL` | Logging verbosity for the publisher/extractor (default: `Information`). Set per environment under **Settings → Environments → Environment variables** |

### Required Repository Settings

Before running the extractor, enable: **Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests"**. This is needed for the extractor to create PRs automatically.

---

## Deployment Flow: Dev to Prod

Here is the complete end-to-end deployment flow:

```
                         ┌──────────────────────┐
                         │  1. Manual Trigger    │
                         │  Run - Extractor      │
                         │  (workflow_dispatch)   │
                         └──────────┬─────────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │  2. Extractor pulls   │
                         │  artifacts from       │
                         │  Dev APIM instance    │
                         └──────────┬─────────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │  3. PR Created        │
                         │  with extracted       │
                         │  artifacts            │
                         └──────────┬─────────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │  4. Developer reviews │
                         │  and merges PR to     │
                         │  main branch          │
                         └──────────┬─────────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │  5. Push to main      │
                         │  triggers Publisher   │
                         │  (automatic)          │
                         └──────────┬─────────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │  6. Publisher deploys │
                         │  to DEV APIM         │
                         │  (no config overrides)│
                         └──────────┬─────────────┘
                                    │
                                    ▼
                         ┌──────────────────────────┐
                         │  7. Dev succeeds →       │
                         │  Publisher deploys to     │
                         │  PROD APIM               │
                         │  (with config overrides   │
                         │  from configuration.      │
                         │  prod.yaml)               │
                         └──────────────────────────┘
```

**Key points:**
- The **extractor** only creates a PR — it does NOT deploy anything
- The **publisher** is what deploys to APIM environments
- The publisher is triggered **automatically** when code is merged to `main`, or **manually** via workflow dispatch
- Dev is always deployed first; prod is deployed only after dev succeeds
- Prod uses `configuration.prod.yaml` for environment-specific overrides
- If environment protection rules (approval gates) are configured on the `prod` environment, a reviewer must approve before the prod deployment proceeds

---

## FAQ: Does the Extractor Run Only Once?

**Not necessarily — but a common and recommended pattern is:**

1. **Initial extraction (one-time bootstrap)**: Run the extractor once against your **dev** APIM instance to populate the repo with all existing API definitions, policies, diagnostics, loggers, etc.
2. **Ongoing changes in code**: After that, manage everything as code in the repo — edit policies, OpenAPI specs, and API configurations directly in the `apimartifacts/` folder.
3. **Publisher runs on merge**: The publisher pipeline deploys those changes to dev, then to prod (using environment-specific overrides).

```
Portal (Dev APIM) ──extractor──▶ Git repo ──publisher──▶ Target APIM (dev/prod)
       ▲                              │
       │                              │ (day-to-day: edit here)
       └── only if portal changes ────┘
```

**When to re-run the extractor:**

- Someone makes changes **directly in the Azure portal** and you need to capture those changes back into code.
- You want to **re-sync** the repo with the actual state of APIM after manual interventions.
- A new API was created in the portal and needs to be brought under source control.

**The ideal workflow**: Run the extractor once to bootstrap, then treat the **Git repo as the single source of truth** and only run the publisher going forward. Re-run the extractor only when out-of-band portal changes need to be captured.

---

## APIM CI/CD Approaches: APIOps vs OpenAPI-in-Code

There are two main ways to set up CI/CD for Azure API Management. Both are valid — the right choice depends on what you're managing and your team's workflow.

### Approach 1: APIOps Extractor/Publisher

**What it manages**: The *entire* APIM configuration — APIs, policies, products, subscriptions, named values, backends, loggers, diagnostics, groups, tags, etc.

**Best for**: Teams that treat APIM as a full platform with complex policies, products, subscriptions, and multi-environment promotion.

| Pros | Cons |
|---|---|
| Manages **everything** in APIM, not just API definitions | Heavier setup — extractor/publisher binaries, more config |
| Built-in multi-environment promotion with config overrides | Extractor can create noisy PRs with unrelated changes |
| Microsoft-supported tooling ([Azure/apiops](https://github.com/Azure/apiops)) | Tightly coupled to APIM's internal structure |
| Handles policies, products, backends, named values, etc. | Learning curve for the artifact folder structure |

**Flow:**

```
Azure Portal (Dev APIM) ──extractor──▶ Git repo ──publisher──▶ Dev APIM ──▶ Prod APIM
```

#### Example: APIOps Publisher Workflow

This workflow uses the APIOps publisher binary to deploy **all** APIM artifacts (APIs, policies, products, backends, named values, etc.) from the `apimartifacts/` folder to Azure.

```yaml
# .github/workflows/run-publisher.yaml
name: Run - Publisher

on:
  push:
    branches:
      - main
  workflow_dispatch:
    inputs:
      COMMIT_ID_CHOICE:
        description: "Publish artifacts from:"
        type: choice
        options:
          - publish-artifacts-in-last-commit
          - publish-all-artifacts-in-repo
        default: publish-artifacts-in-last-commit

env:
  apiops_release_version: v6.0.2

jobs:
  get-commit:
    runs-on: ubuntu-latest
    outputs:
      commit-id: ${{ steps.commit.outputs.commit-id }}
    steps:
      - id: commit
        run: |
          if [[ "${{ github.event.inputs.COMMIT_ID_CHOICE }}" == "publish-all-artifacts-in-repo" ]]; then
            echo "commit-id=" >> "$GITHUB_OUTPUT"
          else
            echo "commit-id=${{ github.sha }}" >> "$GITHUB_OUTPUT"
          fi

  Push-Changes-To-APIM-Dev:
    needs: get-commit
    uses: ./.github/workflows/run-publisher-with-env.yaml
    with:
      API_MANAGEMENT_ENVIRONMENT: dev
      COMMIT_ID: ${{ needs.get-commit.outputs.commit-id }}
      API_MANAGEMENT_SERVICE_OUTPUT_FOLDER_PATH: apimartifacts
    secrets: inherit

  Push-Changes-To-APIM-Prod:
    needs: Push-Changes-To-APIM-Dev
    uses: ./.github/workflows/run-publisher-with-env.yaml
    with:
      API_MANAGEMENT_ENVIRONMENT: prod
      CONFIGURATION_YAML_PATH: configuration.prod.yaml
      COMMIT_ID: ${{ needs.get-commit.outputs.commit-id }}
      API_MANAGEMENT_SERVICE_OUTPUT_FOLDER_PATH: apimartifacts
    secrets: inherit
```

The reusable workflow (`run-publisher-with-env.yaml`) downloads the APIOps publisher binary and runs it:

```yaml
# .github/workflows/run-publisher-with-env.yaml (simplified)
name: Run - Publisher with Environment

on:
  workflow_call:
    inputs:
      API_MANAGEMENT_ENVIRONMENT:
        required: true
        type: string
      CONFIGURATION_YAML_PATH:
        required: false
        type: string
      COMMIT_ID:
        required: false
        type: string
      API_MANAGEMENT_SERVICE_OUTPUT_FOLDER_PATH:
        required: true
        type: string

env:
  apiops_release_version: v6.0.2

jobs:
  publish:
    runs-on: ubuntu-latest
    environment: ${{ inputs.API_MANAGEMENT_ENVIRONMENT }}
    steps:
    - uses: actions/checkout@v4

    - uses: azure/login@v2
      with:
        client-id: ${{ secrets.AZURE_CLIENT_ID }}
        tenant-id: ${{ secrets.AZURE_TENANT_ID }}
        subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

    - name: Download publisher
      run: |
        wget https://github.com/Azure/apiops/releases/download/${{ env.apiops_release_version }}/publisher-linux-x64.zip
        unzip publisher-linux-x64.zip -d publisher
        chmod +x publisher/publisher

    - name: Run publisher
      run: |
        ./publisher/publisher
      env:
        AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
        AZURE_RESOURCE_GROUP_NAME: ${{ secrets.AZURE_RESOURCE_GROUP_NAME }}
        API_MANAGEMENT_SERVICE_NAME: ${{ secrets.API_MANAGEMENT_SERVICE_NAME }}
        API_MANAGEMENT_SERVICE_OUTPUT_FOLDER_PATH: ${{ inputs.API_MANAGEMENT_SERVICE_OUTPUT_FOLDER_PATH }}
        CONFIGURATION_YAML_PATH: ${{ inputs.CONFIGURATION_YAML_PATH }}
        COMMIT_ID: ${{ inputs.COMMIT_ID }}
```

**What gets deployed**: Everything in `apimartifacts/` — API definitions, XML policies, products, backends, named values, loggers, diagnostics, groups, and more.

---

### Approach 2: OpenAPI Spec in Code + Direct Deploy

**What it manages**: The API definition (OpenAPI spec) and optionally a policy file. Everything else (infra, products, backends) is managed via Bicep/Terraform or the portal.

**Best for**: API-first teams where the spec is the source of truth, especially when using TypeSpec or generating OpenAPI from code.

| Pros | Cons |
|---|---|
| API spec is the **true source of truth** — no extraction needed | Only deploys the API definition, not policies/products/backends |
| Works naturally with TypeSpec, code-gen, and API-first workflows | Need separate IaC (Terraform) for non-API APIM resources |
| Simple pipeline — just `az apim api import` | Manual policy management unless you script it |
| Easy to understand and debug | No built-in multi-env config override mechanism |

**Flow:**

```
TypeSpec / OpenAPI (in code) ──az apim api import──▶ Dev APIM ──▶ Prod APIM
Terraform (infra)            ──terraform apply──▶    APIM policies, products, backends
```

#### Example: OpenAPI Direct Deploy Workflow

This workflow imports an OpenAPI spec directly into APIM using the Azure CLI. The spec lives in the repo and can be hand-written or generated from TypeSpec.

```yaml
# .github/workflows/deploy-apim.yaml
name: Deploy API

on:
  push:
    branches:
      - dev
      - main

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - uses: azure/login@v2
      with:
        client-id: ${{ secrets.AZURE_CLIENT_ID }}
        tenant-id: ${{ secrets.AZURE_TENANT_ID }}
        subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

    - name: Set environment
      run: |
        if [[ "${GITHUB_REF##*/}" == "main" ]]; then
          echo "APIM_NAME=${{ secrets.APIM_PROD }}" >> $GITHUB_ENV
        else
          echo "APIM_NAME=${{ secrets.APIM_DEV }}" >> $GITHUB_ENV
        fi

    - name: Deploy API
      run: |
        az apim api import \
          --resource-group ${{ secrets.RESOURCE_GROUP }} \
          --service-name $APIM_NAME \
          --api-id orders-api \
          --path orders \
          --display-name "Orders API" \
          --specification-format OpenApi \
          --specification-path openapi.yaml
```

**What gets deployed**: Only the API definition (operations, schemas, description). Policies, products, and other APIM resources are **not** managed by this workflow.

#### Optional: Pairing with Terraform for Full Management

To manage policies, products, and backends alongside the OpenAPI spec, add Terraform:

```hcl
# infra/main.tf
data "azurerm_api_management" "apim" {
  name                = var.apim_name
  resource_group_name = var.resource_group_name
}

data "azurerm_api_management_api" "orders" {
  name                = "orders-api"
  api_management_name = data.azurerm_api_management.apim.name
  resource_group_name = var.resource_group_name
  revision            = "1"
}

resource "azurerm_api_management_api_policy" "orders_policy" {
  api_name            = data.azurerm_api_management_api.orders.name
  api_management_name = data.azurerm_api_management.apim.name
  resource_group_name = var.resource_group_name

  xml_content = file("${path.module}/../policies/api-policy.xml")
}

resource "azurerm_api_management_product" "starter" {
  product_id          = "starter"
  api_management_name = data.azurerm_api_management.apim.name
  resource_group_name = var.resource_group_name
  display_name        = "Starter"
  published           = true
  subscription_required = true
}

resource "azurerm_api_management_product_api" "starter_orders" {
  api_name            = data.azurerm_api_management_api.orders.name
  product_id          = azurerm_api_management_product.starter.product_id
  api_management_name = data.azurerm_api_management.apim.name
  resource_group_name = var.resource_group_name
}
```

Add a Terraform step to the workflow:

```yaml
    - name: Deploy Terraform (policies, products)
      run: |
        cd infra
        terraform init
        terraform apply -auto-approve \
          -var="apim_name=$APIM_NAME" \
          -var="resource_group_name=${{ secrets.RESOURCE_GROUP }}"
```

---

### Which One Should You Use?

| Scenario | Recommended Approach |
|---|---|
| Greenfield, API-first, TypeSpec | **OpenAPI in code + Terraform** for policies & infra |
| Brownfield, lots of existing portal config | **APIOps extractor/publisher** to bootstrap, then optionally transition |
| Only managing API definitions, simple policies | **OpenAPI in code + `az apim api import`** |
| Full platform management (products, subscriptions, backends, etc.) | **APIOps** or **Terraform** |

**Industry trend**: The direction is moving toward **API-first (Approach 2)** combined with IaC. TypeSpec or OpenAPI as the source of truth, Terraform for infrastructure, and simple CLI-based deployment pipelines.

**APIOps** remains valuable for brownfield scenarios where you need to quickly bring existing portal-configured APIM resources under source control.

---

## Terraform for APIM CI/CD

Terraform is a popular Infrastructure as Code (IaC) tool that can manage **the entire lifecycle** of your APIM resources — from the APIM instance itself to APIs, policies, products, backends, named values, and more.

### Can Terraform Replace the APIOps Extractor/Publisher?

**Short answer: No — they solve different problems, but Terraform can be an alternative for the Publisher side.**

| Capability | APIOps Extractor | APIOps Publisher | Terraform |
|---|---|---|---|
| **Extract existing APIM config into code** | Yes | No | **No** (use `aztfexport` for one-time import) |
| **Deploy API definitions from OpenAPI specs** | No | Yes | Yes (`azurerm_api_management_api`) |
| **Deploy policies, products, backends, etc.** | No | Yes | Yes (full resource coverage) |
| **Multi-environment promotion** | No | Yes (via config YAML overrides) | Yes (via `.tfvars` per environment) |
| **Drift detection** | No | No | **Yes** (`terraform plan` shows drift) |
| **State management** | No (stateless) | No (stateless) | **Yes** (tracks resource state) |
| **Destroy/remove resources** | No | No | **Yes** (`terraform destroy`) |

**Key differences:**

- **APIOps Extractor** has no Terraform equivalent. Terraform cannot "extract" your existing APIM configuration into `.tf` files. However, you can use [`aztfexport`](https://github.com/Azure/aztfexport) as a one-time bootstrap to generate Terraform code from existing Azure resources.
- **APIOps Publisher** can be replaced by Terraform. Both push configuration to APIM. Terraform adds drift detection and state management, but requires learning HCL and managing state files.
- **Terraform excels** at managing the full infrastructure stack (APIM instance + networking + APIs + policies) in a single tool, especially for greenfield projects.

### How Terraform Works for APIM

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     Terraform APIM CI/CD Flow                           │
│                                                                         │
│  1. WRITE: Define APIM resources in .tf files (APIs, policies, etc.)    │
│                                                                         │
│  2. PLAN: terraform plan shows what will change                         │
│     (drift detection — shows if someone changed APIM in the portal)     │
│                                                                         │
│  3. APPLY: terraform apply deploys changes to APIM                      │
│     (only changes what's different — idempotent)                        │
│                                                                         │
│  4. PROMOTE: Use different .tfvars for dev vs prod                      │
│     dev.tfvars  → Dev APIM                                              │
│     prod.tfvars → Prod APIM                                             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Multi-environment with `.tfvars`:**

```hcl
# infra/dev.tfvars
apim_name           = "contiworkshopapimdev"
resource_group_name = "rg-apim-dev"
backend_url         = "https://api-dev.contoso.com"

# infra/prod.tfvars
apim_name           = "contiworkshopapimprod"
resource_group_name = "rg-apim-prod"
backend_url         = "https://api.contoso.com"
```

This is the Terraform equivalent of APIOps' `configuration.prod.yaml` overrides.

### Defining APIs in Terraform: Import from File vs Inline

With Terraform you **don't need** the APIOps extractor/publisher at all. You define your API, policies, products, subscriptions, and backends directly in `.tf` files. But there are two ways to define the API itself:

#### Option 1: Import API from an OpenAPI Spec File (Recommended)

Keep your OpenAPI spec as a separate `.yaml` file and import it into Terraform. The spec is the source of truth — all operations, schemas, and descriptions come from the file.

```hcl
resource "azurerm_api_management_api" "orders" {
  name                = "orders-api"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "Orders API"
  path                = "orders"
  protocols           = ["https"]

  import {
    content_format = "openapi"           # or "openapi+yaml" for YAML format
    content_value  = file("./api_specs/orders-api.yaml")
  }
}
```

#### Option 2: Define Operations Inline in Terraform

Define each operation manually as a separate `azurerm_api_management_api_operation` resource. No OpenAPI file needed.

```hcl
resource "azurerm_api_management_api" "orders" {
  name                = "orders-api"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "Orders API"
  path                = "orders"
  protocols           = ["https"]
}

resource "azurerm_api_management_api_operation" "get_orders" {
  operation_id        = "get-orders"
  api_name            = azurerm_api_management_api.orders.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = var.resource_group_name
  display_name        = "Get Orders"
  method              = "GET"
  url_template        = "/orders"

  response {
    status_code = 200
  }
}
```

#### Which is Better?

| | Option 1: Import from OpenAPI File | Option 2: Inline in Terraform |
|---|---|---|
| **API definition** | OpenAPI spec (industry standard, portable) | HCL (locked to Terraform) |
| **Reusability** | Spec can be shared with frontend, docs, SDK gen | Only usable within Terraform |
| **Complexity** | 1 resource per API regardless of operations | 1 resource **per operation** — verbose |
| **TypeSpec compatible** | Yes — generate OpenAPI, import it | No |
| **10 operations?** | Still 1 `import` block | 10 separate `azurerm_api_management_api_operation` resources |
| **Policies** | Separate XML files (easy to read/edit) | Can be inline or separate (same either way) |

**Option 1 is better in almost every case.** The OpenAPI spec remains portable and reusable, scaling is trivial, and you don't lock your API definition inside Terraform HCL.

### Example: Full APIM Management with Terraform

This example manages the APIM instance, an API (imported from an OpenAPI spec), policies, a product, a subscription, API versioning, a backend, and a named value — **all in Terraform**.

```hcl
# infra/variables.tf
variable "apim_name" {
  description = "Name of the APIM instance"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "backend_url" {
  description = "Backend API URL"
  type        = string
}

variable "publisher_email" {
  description = "APIM publisher email"
  type        = string
}

variable "publisher_name" {
  description = "APIM publisher name"
  type        = string
}
```

```hcl
# infra/main.tf
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    # Configure remote state storage
    # resource_group_name  = "rg-terraform-state"
    # storage_account_name = "tfstateapim"
    # container_name       = "tfstate"
    # key                  = "apim.tfstate"
  }
}

provider "azurerm" {
  features {}
}

# ─── Resource Group ──────────────────────────────────────────
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# ─── APIM Instance ───────────────────────────────────────────
resource "azurerm_api_management" "apim" {
  name                = var.apim_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  publisher_email     = var.publisher_email
  publisher_name      = var.publisher_name
  sku_name            = "Developer_1"
}

# ─── API Version Set (optional, for versioned APIs) ─────────
resource "azurerm_api_management_api_version_set" "orders_version_set" {
  name                = "orders-api-version-set"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  display_name        = "Orders API"
  versioning_scheme   = "Segment"   # version appears in URL path: /orders/v1/...
}

# ─── API (imported from OpenAPI spec file) ───────────────────
# The API definition comes from the OpenAPI YAML file.
# Terraform does NOT define the operations — the spec file does.
resource "azurerm_api_management_api" "orders" {
  name                = "orders-api"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  revision            = "1"
  display_name        = "Orders API"
  path                = "orders"
  protocols           = ["https"]

  # Versioning (optional — omit version_set_id and version if not using versioning)
  version_set_id = azurerm_api_management_api_version_set.orders_version_set.id
  version        = "v1"

  import {
    content_format = "openapi"                                  # "openapi" for YAML, "openapi+json" for JSON
    content_value  = file("${path.module}/../api_specs/orders-api.yaml")
  }
}

# ─── API Policy ──────────────────────────────────────────────
resource "azurerm_api_management_api_policy" "orders_policy" {
  api_name            = azurerm_api_management_api.orders.name
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name

  xml_content = file("${path.module}/../policies/api-policy.xml")
}

# ─── Backend ─────────────────────────────────────────────────
resource "azurerm_api_management_backend" "orders_backend" {
  name                = "orders-backend"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  protocol            = "http"
  url                 = var.backend_url
}

# ─── Product ─────────────────────────────────────────────────
# A product groups APIs and controls access via subscriptions.
resource "azurerm_api_management_product" "orders_product" {
  product_id            = "orders-product"
  api_management_name   = azurerm_api_management.apim.name
  resource_group_name   = azurerm_resource_group.rg.name
  display_name          = "Orders API Product"
  subscription_required = true
  approval_required     = false
  published             = true     # makes it visible in the developer portal
}

# ─── Add API to Product ──────────────────────────────────────
resource "azurerm_api_management_product_api" "orders_product_api" {
  api_name            = azurerm_api_management_api.orders.name
  product_id          = azurerm_api_management_product.orders_product.product_id
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
}

# ─── Subscription ────────────────────────────────────────────
# Creates a subscription key scoped to this specific API.
resource "azurerm_api_management_subscription" "orders_subscription" {
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.rg.name
  display_name        = "Orders API Subscription"
  api_id              = azurerm_api_management_api.orders.id
  state               = "active"
  allow_tracing       = false
}

# ─── Named Value ─────────────────────────────────────────────
resource "azurerm_api_management_named_value" "api_key" {
  name                = "api-key"
  resource_group_name = azurerm_resource_group.rg.name
  api_management_name = azurerm_api_management.apim.name
  display_name        = "api-key"
  value               = var.backend_url   # or reference a Key Vault secret
  secret              = true
}
```

**Key takeaway**: Terraform imports the API definition from the OpenAPI spec file — it does **not** define the API operations itself. The `.yaml` spec is the source of truth for operations, schemas, and descriptions. Terraform manages everything around it: policies, products, subscriptions, backends, and named values.

### Example: Terraform CI/CD Workflow

```yaml
# .github/workflows/deploy-terraform.yaml
name: Deploy APIM (Terraform)

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

permissions:
  id-token: write
  contents: read
  pull-requests: write

env:
  TF_WORKING_DIR: infra
  ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  ARM_USE_OIDC: true

jobs:
  # ─── Plan (runs on PRs and pushes) ─────────────────────────
  plan:
    name: Terraform Plan
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - uses: hashicorp/setup-terraform@v3
      with:
        terraform_version: 1.9.0

    - uses: azure/login@v2
      with:
        client-id: ${{ secrets.AZURE_CLIENT_ID }}
        tenant-id: ${{ secrets.AZURE_TENANT_ID }}
        subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

    - name: Terraform Init
      working-directory: ${{ env.TF_WORKING_DIR }}
      run: terraform init

    - name: Terraform Plan (Dev)
      working-directory: ${{ env.TF_WORKING_DIR }}
      run: terraform plan -var-file=dev.tfvars -out=dev.tfplan

    - name: Terraform Plan (Prod)
      working-directory: ${{ env.TF_WORKING_DIR }}
      run: terraform plan -var-file=prod.tfvars -out=prod.tfplan

  # ─── Deploy Dev (only on push to main) ─────────────────────
  deploy-dev:
    name: Deploy to Dev
    needs: plan
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: dev
    steps:
    - uses: actions/checkout@v4

    - uses: hashicorp/setup-terraform@v3
      with:
        terraform_version: 1.9.0

    - uses: azure/login@v2
      with:
        client-id: ${{ secrets.AZURE_CLIENT_ID }}
        tenant-id: ${{ secrets.AZURE_TENANT_ID }}
        subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

    - name: Terraform Init & Apply (Dev)
      working-directory: ${{ env.TF_WORKING_DIR }}
      run: |
        terraform init
        terraform apply -auto-approve -var-file=dev.tfvars

  # ─── Deploy Prod (after Dev succeeds) ──────────────────────
  deploy-prod:
    name: Deploy to Prod
    needs: deploy-dev
    runs-on: ubuntu-latest
    environment: prod  # requires approval if protection rules are set
    steps:
    - uses: actions/checkout@v4

    - uses: hashicorp/setup-terraform@v3
      with:
        terraform_version: 1.9.0

    - uses: azure/login@v2
      with:
        client-id: ${{ secrets.AZURE_CLIENT_ID }}
        tenant-id: ${{ secrets.AZURE_TENANT_ID }}
        subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

    - name: Terraform Init & Apply (Prod)
      working-directory: ${{ env.TF_WORKING_DIR }}
      run: |
        terraform init
        terraform apply -auto-approve -var-file=prod.tfvars
```

**How this works:**

1. **On PRs**: Runs `terraform plan` for both environments — reviewers can see exactly what will change before merging.
2. **On merge to main**: Runs `terraform apply` for dev first, then prod (with optional approval gate).
3. **Drift detection**: If someone changed APIM in the portal, `terraform plan` will show it — you can decide to accept or revert.
4. **Multi-environment**: `dev.tfvars` and `prod.tfvars` provide environment-specific values (same concept as APIOps' `configuration.prod.yaml`).

### Terraform vs APIOps: Side-by-Side

| Feature | APIOps (Extractor + Publisher) | Terraform |
|---|---|---|
| **Bootstrap from existing APIM** | Extractor (built-in) | `aztfexport` (one-time, separate tool) |
| **Deploy APIs from OpenAPI** | Publisher reads `apimartifacts/` | `azurerm_api_management_api` with `import` block |
| **Deploy policies** | Publisher reads `policy.xml` files | `azurerm_api_management_api_policy` |
| **Multi-env config** | `configuration.{env}.yaml` | `{env}.tfvars` |
| **Drift detection** | None | `terraform plan` |
| **State tracking** | Stateless (idempotent push) | Stateful (`.tfstate` file) |
| **Remove deleted resources** | Must be done manually or via portal | `terraform apply` removes resources deleted from code |
| **Learning curve** | APIOps artifact structure + YAML | HCL + Terraform workflow |
| **CI/CD integration** | Download binary + run | `terraform init` + `plan` + `apply` |
| **Manage non-APIM resources** | No (APIM only) | Yes (full Azure stack — networking, compute, etc.) |

**When to use Terraform over APIOps:**
- You already use Terraform for other Azure infrastructure
- You want drift detection and state management
- You want a single IaC tool for everything (APIM + networking + backends + databases)
- You're building greenfield and don't need to extract existing config

**When to stick with APIOps:**
- You have a large existing APIM instance and need the extractor to bootstrap
- Your team works primarily in the Azure portal and wants a sync mechanism
- You want a simpler, purpose-built tool without managing Terraform state

---

## References

- [APIOps Toolkit (GitHub)](https://github.com/Azure/APIOps)
- [APIOps Documentation](https://azure.github.io/apiops/)
- [Extract APIM Artifacts (GitHub)](https://azure.github.io/apiops/apiops/4-extractApimArtifacts/apiops-github-3-2.html)
- [Publish APIM Artifacts (GitHub)](https://azure.github.io/apiops/apiops/5-publishApimArtifacts/apiops-github-4-2-pipeline.html)
- [Configure APIM Tools](https://azure.github.io/apiops/apiops/3-apimTools/apiops-2-2-tools-publisher.html)
- [APIOps Releases](https://github.com/Azure/APIOps/releases)
- [Azure API Management Documentation](https://learn.microsoft.com/en-us/azure/api-management/)
