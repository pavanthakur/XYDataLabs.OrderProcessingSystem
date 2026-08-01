using System.Reflection;

namespace XYDataLabs.OrderProcessingSystem.API;

public sealed class AssemblyReference
{
    public static Assembly Assembly => typeof(AssemblyReference).Assembly;
}
