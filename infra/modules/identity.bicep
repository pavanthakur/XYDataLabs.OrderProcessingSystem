// Simplified placeholder identity module.
// Rationale: Full OIDC App Registration + Federated Credential automation via deploymentScript
// introduced parsing errors and is deferred until directory Graph permissions are granted.
// This stub allows the main template to compile with `enableIdentity=false`.
// Future Enhancement: Replace with deploymentScript or native resources once supported/authorized.

@description('GitHub owner/org (placeholder)')
param githubOwner string
@description('GitHub repository name (placeholder)')
param githubRepo string
@description('Environment code')
param environment string

// Output empty clientId so main template conditional output remains valid.
output clientId string = ''
