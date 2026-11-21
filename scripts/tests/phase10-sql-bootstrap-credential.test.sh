#!/usr/bin/env bash
set -euo pipefail

az() {
  case "$1 $2" in
    'group exists') [[ "$SCENARIO" != arm-error ]] || return 1; echo true ;;
    'sql server') if [[ "$SCENARIO" != fresh ]]; then echo orderprocessing-sql-dev; fi ;;
    'keyvault secret')
      case "$SCENARIO" in
        denied) return 1 ;;
        malformed) echo 'unsafe;fixture' ;;
        *) echo ExistingFixtureAa1! ;;
      esac ;;
    *) return 1 ;;
  esac
}
openssl() {
  [[ "$SCENARIO" == fresh ]] || return 1
  echo 0123456789abcdef0123456789abcdef
}
export -f az openssl
export GITHUB_OUTPUT=/dev/stdout
resolver=(bash scripts/resolve-phase10-sql-bootstrap-credential.sh rg-orderprocessing-dev orderprocessing-sql-dev kv-orderprocessing-dev)

result=$(SCENARIO=fresh "${resolver[@]}" 2>&1)
[[ "$result" == *'source=new'* && "$result" == *'sqlAdminPassword=0123456789abcdef0123456789abcdefAa1!'* ]]
result=$(SCENARIO=existing "${resolver[@]}" 2>&1)
[[ "$result" == *'source=existing'* && "$result" == *'sqlAdminPassword=ExistingFixtureAa1!'* ]]
for scenario in denied malformed arm-error; do
  if result=$(SCENARIO="$scenario" "${resolver[@]}" 2>&1); then
    echo "Expected refusal for $scenario" >&2
    exit 1
  fi
  [[ "$result" != *'sqlAdminPassword='* && "$result" != *'unsafe;fixture'* ]]
done
echo 'SQL bootstrap credential resolver: 5 mocked cases passed.'
