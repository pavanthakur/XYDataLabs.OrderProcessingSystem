using System;
using System.Collections.Generic;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests
{
    public class BuildErrorClassifier
    {
        private static readonly Dictionary<string, string> ErrorClassifications = new Dictionary<string, string>
        {
            { "CS0128", "Local variable 'variableName' is already declared" },
            { "CS0136", "A local or parameter named 'parameterName' cannot be declared in this scope because that name is used in an enclosing block to declare a local or parameter" },
            // Add more error codes and classifications as needed
        };

        public static string ClassifyError(string errorCode)
        {
            if (ErrorClassifications.TryGetValue(errorCode, out var classification))
            {
                return classification;
            }
            else
            {
                return "Unknown error";
            }
        }
    }
}
