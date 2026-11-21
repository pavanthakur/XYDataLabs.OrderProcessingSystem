#!/usr/bin/env bash
set -euo pipefail

rg_name="${1:?Expected resource group}"
server="${2:?Expected SQL server}"
vault="${3:?Expected Key Vault}"

group_exists=$(az group exists --name "$rg_name" -o tsv)
case "$group_exists" in
  true) server_name=$(az sql server list --resource-group "$rg_name" --query "[?name=='$server'].name | [0]" -o tsv) ;;
  false) server_name='' ;;
  *) echo 'Could not determine whether the SQL resource group exists.' >&2; exit 1 ;;
esac

if [[ -n "$server_name" ]]; then
  if [[ "$server_name" != "$server" ]] || ! password=$(az keyvault secret show --vault-name "$vault" --name sql-admin-password --query value -o tsv 2>/dev/null); then
    echo 'Existing SQL server requires a readable SQL bootstrap credential in its environment Key Vault; refusing to generate a replacement.' >&2
    exit 1
  fi
  source=existing
else
  password="$(openssl rand -hex 16)Aa1!"
  source=new
fi

# Only accept the workflow-owned credential format, safe for the existing SQL
# connection-string consumers and single-line GitHub output. Never emit a raw error/value.
if [[ ! "$password" =~ ^[A-Za-z0-9]+Aa1!$ ]]; then
  echo 'SQL bootstrap credential is missing or not in the workflow-owned format; review credential recovery separately.' >&2
  exit 1
fi
printf '::add-mask::%s\n' "$password"
printf 'sqlAdminPassword=%s\n' "$password" >> "$GITHUB_OUTPUT"
printf 'source=%s\n' "$source" >> "$GITHUB_OUTPUT"
printf 'SQL bootstrap credential source: %s server.\n' "$source"
