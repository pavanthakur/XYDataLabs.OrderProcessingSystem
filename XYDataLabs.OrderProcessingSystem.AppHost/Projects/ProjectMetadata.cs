using Aspire.Hosting;

namespace Projects;

// Minimal Aspire project metadata for offline builds.
// The Aspire source generator is not producing the referenced project types in this environment,
// so we define the project metadata explicitly to keep AddProject<T>() working.
public class XyDataLabsOrderProcessingSystemApi
    : IProjectMetadata
{
    public XyDataLabsOrderProcessingSystemApi()
    {
    }

    public string ProjectPath => @"Q:\GIT\TestAppXY_OrderProcessingSystem\XYDataLabs.OrderProcessingSystem.API";
}

public class XyDataLabsOrderProcessingSystemGateway
    : IProjectMetadata
{
    public XyDataLabsOrderProcessingSystemGateway()
    {
    }

    public string ProjectPath => @"Q:\GIT\TestAppXY_OrderProcessingSystem\XYDataLabs.OrderProcessingSystem.Gateway";
}
