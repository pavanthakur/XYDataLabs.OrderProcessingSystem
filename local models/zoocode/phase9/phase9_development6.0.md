# Phase 9 Development 6.0 - Gateway And YARP Slice

Zoo role: Implementer.

Strict mode: implement only this slice. Do not ask follow-up questions. Do not invent architecture. Finish with `DONE`.

Input:

- Accepted output from `phase9_architect2.0.md`
- Existing `XYDataLabs.OrderProcessingSystem.Gateway` project
- YARP configuration files and tests

Task:

Validate or adjust YARP gateway configuration for Phase 9 boundaries.

Hard constraints:

- YARP routes HTTP traffic to host boundaries, not class-library modules.
- During module isolation, gateway may continue routing to the existing API host.
- Do not add routes to independently hosted module APIs until those hosts exist and tests prove they work.
- Use standard YARP shape: `ReverseProxy:Routes` and `ReverseProxy:Clusters`.

Allowed changes:

- Gateway tests.
- YARP config corrections only when current config is invalid or explicitly accepted.
- Documentation comments in gateway config only if the repository style allows them.

Forbidden changes:

- No pseudo-route config such as route keys named `/api/orders/*` with `Destination` directly under the route.
- No new service host projects in this slice.

Validation command:

```powershell
dotnet test tests/XYDataLabs.OrderProcessingSystem.Gateway.Tests/XYDataLabs.OrderProcessingSystem.Gateway.Tests.csproj
```
