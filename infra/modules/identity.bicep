@description('GitHub owner/org')
param githubOwner string
@description('GitHub repository name')
param githubRepo string
@description('Environment')
param environment string

// NOTE: Native Microsoft.Graph app registration is not fully supported via ARM/Bicep yet.
// We use a deploymentScript to invoke Azure CLI for App Registration + Federated Credentials.
// This script is idempotent: re-running will reuse existing resources.

var appDisplayName = 'GitHub-Actions-OIDC'
var branchList = [ 'dev' 'staging' 'main' ]

resource oidcScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'oidc-script-${environment}'
  location: resourceGroup().location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    // In production, reference a pre-created user-assigned managed identity with Graph permissions.
    // For demo purposes this is left abstract; you must grant required directory permissions manually.
  }
  properties: {
    azCliVersion: '2.63.0'
    timeout: 'PT30M'
    retentionInterval: 'P1D'
    scriptContent: '''
appId=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
if [ -z "$appId" ]; then
  echo "Creating app registration $APP_NAME" >&2
  appId=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
fi
spId=$(az ad sp list --filter "appId eq '$appId'" --query "[0].id" -o tsv)
if [ -z "$spId" ]; then
  echo "Creating service principal for $appId" >&2
  az ad sp create --id $appId >/dev/null
fi
# Federated credentials
for br in ${BRANCHES}; do
  name="github-$br-oidc"
  exists=$(az ad app federated-credential list --id $appId --query "[?name=='$name'].name" -o tsv)
  if [ -z "$exists" ]; then
    subj="repo:${GITHUB_OWNER}/${GITHUB_REPO}:ref:refs/heads/$br"
    echo "Creating federated credential $name for $subj" >&2
    cat > params.json <<EOF
    {"name":"$name","issuer":"https://token.actions.githubusercontent.com","subject":"$subj","audiences":["api://AzureADTokenExchange"]}
EOF
    az ad app federated-credential create --id $appId --parameters params.json >/dev/null
    rm params.json
  else
    echo "Federated credential $name already exists" >&2
  fi
done

echo "APP_ID=$appId" >> $AZ_SCRIPTS_OUTPUT_PATH
'''
    arguments: '--environment ${environment}'
    supportingScriptUris: []
    environmentVariables: [
      {
        name: 'APP_NAME'
        value: appDisplayName
      }
      {
        name: 'GITHUB_OWNER'
        value: githubOwner
      }
      {
        name: 'GITHUB_REPO'
        value: githubRepo
      }
      {
        name: 'BRANCHES'
        value: join(' ', branchList)
      }
    ]
  }
}

output clientId string = oidcScript.properties.outputs.APP_ID
