using System.Reflection;
using Microsoft.AspNetCore.Mvc.Controllers;

namespace XYDataLabs.OrderProcessingSystem.API.Hosting;

public sealed class OwnedControllerFeatureProvider(IEnumerable<Type> controllerTypes)
    : ControllerFeatureProvider
{
    private readonly HashSet<Type> _controllerTypes = controllerTypes.ToHashSet();

    protected override bool IsController(TypeInfo typeInfo)
        => _controllerTypes.Contains(typeInfo.AsType()) && base.IsController(typeInfo);
}
