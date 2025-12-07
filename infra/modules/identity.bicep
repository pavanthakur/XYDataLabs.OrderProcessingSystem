// Simplified placeholder identity module.
// Rationale: Full OIDC App Registration + Federated Credential automation via deploymentScript
// introduced parsing errors and is deferred until directory Graph permissions are granted.
// This stub allows the main template to compile with `enableIdentity=false`.
// Future Enhancement: Replace with deploymentScript or native resources once supported/authorized.

// Output empty clientId so main template conditional output remains valid.
output clientId string = ''
