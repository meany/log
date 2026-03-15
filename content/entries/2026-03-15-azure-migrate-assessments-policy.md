---
date: 2026-03-15
title: "locking down Azure Migrate assessments"
tags:
  - azure
  - policy
  - ops
author: "system"
slug: "2026-03-15-azure-migrate-assessments-policy"
summary: "Notes from setting up an Azure Migrate Assessments subscription and assigning an allowed-resource-types policy at management group scope."
featured_image: "/entries/2026-03-15-azure-migrate-assessments-policy/og.png"
ai_note: true
draft: false
---
## Summary

Set up an `Azure Migrate Assessments` subscription model with a policy guardrail at
the management group layer. The goal was to deny resource creation outside the
resource providers needed for Azure Migrate assessment workflows.

Finding the right policy set took a while. The working approach was to use the
built-in `Allowed resource types` policy definition, assign it at management
group scope, then update the allowed list.

**Why this matters:** Azure Migrate assessment resources should stay effectively
cost-free, so this pattern helps prevent drift and quickly alerts if any
unexpected spend appears.

## Prerequisites

- Run commands from Azure Cloud Shell (Bash) or another Bash environment with
  Azure CLI installed.
- Sign in and target the right tenant and subscription context.
- Have permissions to manage policy at management group scope and budgets at
  subscription scope (for example, Policy Contributor + Cost Management
  Contributor).

## Policy

Get the built-in definition ID:

```bash
POLICY_DEF_ID="$(az policy definition list \
  --query "[?displayName=='Allowed resource types'].id | [0]" \
  -o tsv)"
```

Create the minimal policy assignment at management group scope:

```bash
MG_NAME="<azure-assessments-mg-name>"
SCOPE="/providers/Microsoft.Management/managementGroups/${MG_NAME}"
ASSIGNMENT_NAME="allow-only-Azure-Migrate-resource-types"

az policy assignment create \
  --name "${ASSIGNMENT_NAME}" \
  --display-name "Allow only approved resource types for Azure Migrate assessments" \
  --scope "${SCOPE}" \
  --policy "${POLICY_DEF_ID}" \
  --params '{"listOfResourceTypesAllowed":{"value":["Microsoft.Resources/subscriptions"]}}'
```

List existing assignments on the management group and copy the assignment `name`:

```bash
az policy assignment list --management-group "${MG_NAME}"
```

For `az policy assignment update`, `--name` must be the assignment `name` value
from the list output (a 24-character hexadecimal ID).

Set the full allowed resource type list on the assignment:

```bash
az policy assignment update --scope "${SCOPE}" --name "<assignment-name-id>" --params '{"listOfResourceTypesAllowed": {"value": [
"Microsoft.AppAssessment/*",
"Microsoft.ApplicationMigration/*",
"Microsoft.Authorization/*",
"Microsoft.Consumption/budgets",
"Microsoft.CostManagement/budgets",
"Microsoft.DataReplication/replicationVaults",
"Microsoft.DependencyMap/*",
"Microsoft.KeyVault/*",
"Microsoft.ManagedIdentity/*",
"Microsoft.Migrate/*",
"Microsoft.MySQLDiscovery/*",
"Microsoft.OffAzure/*",
"Microsoft.RecoveryServices/*",
"Microsoft.Resources/deployments",
"Microsoft.Resources/subscriptions",
"Microsoft.Resources/subscriptions/*",
"Microsoft.Storage/storageAccounts",
"Microsoft.Storage/storageAccounts/blobServices"
]}}'
```

You can set this `value` during policy creation. I landed on this list only after
creating an Azure Migrate project, adding an appliance, and setting workload
scopes.

This policy can also block future Azure Migrate dependencies if Microsoft adds
new resource types, so revisit the allow list periodically.

## Budget

Since Azure Migrate resources do not incur spend, creating a $1 monthly budget
to send email alerts helps validate this.

```bash
SUBSCRIPTION_ID="<azure-migrate-subscription-id>"
ALERT_EMAIL="alerts@example.com"
BUDGET_NAME="azure-migrate-guardrail-1usd"
START_DATE="$(date -u +%Y-%m-01)"

NOTIFICATIONS_JSON="$(cat <<EOF
{
  "actual": {
    "enabled": true,
    "operator": "GreaterThan",
    "threshold": 100,
    "thresholdType": "Actual",
    "contactEmails": ["${ALERT_EMAIL}"]
  },
  "forecast": {
    "enabled": true,
    "operator": "GreaterThan",
    "threshold": 100,
    "thresholdType": "Forecasted",
    "contactEmails": ["${ALERT_EMAIL}"]
  }
}
EOF
)"

az consumption budget create \
  --subscription "${SUBSCRIPTION_ID}" \
  --budget-name "${BUDGET_NAME}" \
  --amount 1 \
  --category cost \
  --time-grain monthly \
  --start-date "${START_DATE}" \
  --notifications "${NOTIFICATIONS_JSON}"

az consumption budget show \
  --subscription "${SUBSCRIPTION_ID}" \
  --budget-name "${BUDGET_NAME}"
```

Budget notifications are not always immediate. In practice, there can be a delay
before actual and forecasted alerts are sent.

## Verification

1. Confirm assignment exists at management group scope.
2. Confirm `listOfResourceTypesAllowed` is set as expected.
3. Confirm budget exists with both `Actual` and `Forecasted` notifications.
4. Trigger a safe validation action and verify no unexpected denials.

```bash
az policy assignment show --name "${ASSIGNMENT_NAME}" --scope "${SCOPE}"
az consumption budget show --subscription "${SUBSCRIPTION_ID}" --budget-name "${BUDGET_NAME}"
```

## Troubleshooting

- If deployment is denied, check Activity Log and the policy assignment details
  to identify the exact blocked resource type.
- If budget creation fails, confirm the `Microsoft.Consumption/budgets` resource
  type is included in the allowed list.

## Notes

- `Allowed resource types` denies resource creation for any type not in
  `listOfResourceTypesAllowed`.
- `az policy assignment list --management-group "${MG_NAME}"` helps discover
  existing assignment names when you are troubleshooting old assignments.
