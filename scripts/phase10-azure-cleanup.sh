#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  dev|prod) suffix="$1" ;;
  staging) suffix=stg ;;
  *) echo 'Refusing cleanup: expected dev, staging, or prod.' >&2; exit 1 ;;
esac

group="rg-orderprocessing-${suffix}"
vault="kv-orderprocessing-${suffix}"
group_status='Not verified'
vault_status='Not verified'
: "${GITHUB_STEP_SUMMARY:?A workflow summary path is required}"

summary() {
  {
    printf '## Phase 10 environment cleanup\n\n'
    printf '| Scope | Outcome |\n|---|---|\n'
    printf '| %s | %s |\n' "$group" "$group_status"
    printf '| %s soft-delete reservation | %s |\n' "$vault" "$vault_status"
    printf '| Shared platform ACR and pull identity | Intentionally retained (outside cleanup scope) |\n'
  } >> "$GITHUB_STEP_SUMMARY"
}
trap summary EXIT

fail() { echo "$1" >&2; exit 1; }

expected_subscription=${CLEANUP_EXPECTED_SUBSCRIPTION_ID:-}
[[ "$expected_subscription" =~ ^[[:xdigit:]]{8}(-[[:xdigit:]]{4}){3}-[[:xdigit:]]{12}$ ]] ||
  fail 'Cleanup requires the configured Azure subscription ID.'
subscription=$(az account show --query id -o tsv --only-show-errors) || fail 'Could not resolve the Azure CLI subscription.'
[[ "${subscription,,}" == "${expected_subscription,,}" ]] ||
  fail 'Active Azure CLI subscription does not match the configured cleanup subscription.'

group_exists() {
  az group exists --name "$group" --subscription "$subscription" --only-show-errors -o tsv
}

exists=$(group_exists) || fail 'Could not check the target resource group before cleanup.'
had_vault=0
case "$exists" in
  true)
    had_vault=$(az resource list --resource-group "$group" --resource-type Microsoft.KeyVault/vaults \
      --query "[?name=='${vault}'] | length(@)" --subscription "$subscription" --only-show-errors -o tsv) ||
      fail 'Could not inventory the environment Key Vault before deletion.'
    [[ "$had_vault" == 0 || "$had_vault" == 1 ]] || fail 'Unexpected Key Vault inventory response.'
    az group delete --name "$group" --subscription "$subscription" --yes --only-show-errors ||
      fail 'Resource group deletion failed.'
    ;;
  false) ;;
  *) fail 'Unexpected resource group existence response.' ;;
esac

exists=$(group_exists) || fail 'Could not verify resource group absence after cleanup.'
if [[ "$exists" == true ]]; then
  group_status='Still present'
fi
[[ "$exists" == false ]] || fail 'Resource group absence not verified; no Key Vault purge attempted.'
group_status='Verified absent'

deleted_vault() {
  az keyvault list-deleted --resource-type vault --subscription "$subscription" --only-show-errors \
    --query "[?name=='${vault}'].[properties.vaultId,properties.location]" -o tsv
}

# A vault present before deletion can take time to appear in the deleted-vault list.
reservation=''
for ((attempt=1; attempt<=30; attempt++)); do
  reservation=$(deleted_vault) || fail 'Could not query the deleted Key Vault reservation.'
  if [[ -n "$reservation" || "$had_vault" == 0 ]]; then break; fi
  if ((attempt < 30)); then sleep 10; fi
done
if [[ -z "$reservation" ]]; then
  [[ "$had_vault" == 0 ]] || fail 'Expected soft-deleted Key Vault never appeared; reservation state not verified.'
  vault_status='No reservation observed (no active target vault before cleanup)'
  exit 0
fi

vault_status='Reservation observed; purge not verified'
vault_id="/subscriptions/${subscription}/resourceGroups/${group}/providers/Microsoft.KeyVault/vaults/${vault}"
observed_id=${reservation%%$'\t'*}
location=${reservation#*$'\t'}
[[ "${observed_id,,}" == "${vault_id,,}" && "$location" =~ ^[a-z0-9]+$ ]] ||
  fail 'Deleted vault ownership or location could not be verified; no purge attempted.'

az keyvault purge --name "$vault" --location "$location" --subscription "$subscription" --only-show-errors ||
  fail 'Key Vault purge failed.'
for ((attempt=1; attempt<=30; attempt++)); do
  reservation=$(deleted_vault) || fail 'Could not verify reservation absence after purge.'
  if [[ -z "$reservation" ]]; then
    vault_status='Purged and verified absent'
    exit 0
  fi
  if ((attempt < 30)); then sleep 10; fi
done
fail 'Key Vault reservation is still present after the bounded verification window.'
