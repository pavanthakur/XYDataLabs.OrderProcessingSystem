using System;
using Xunit;

namespace XYDataLabs.OrderProcessingSystem.Architecture.Tests
{
    public class BuildErrorClassifierTests
    {
        [Fact]
        public void ClassifyError_Should_Return_Correct_Classification()
        {
            var errorCode = "CS0128";
            var expectedClassification = "Local variable 'variableName' is already declared";

            var classification = BuildErrorClassifier.ClassifyError(errorCode);

            Assert.Equal(expectedClassification, classification);
        }

        [Fact]
        public void ClassifyError_Should_Return_Unknown_Error()
        {
            var errorCode = "CS1234";
            var expectedClassification = "Unknown error";

            var classification = BuildErrorClassifier.ClassifyError(errorCode);

            Assert.Equal(expectedClassification, classification);
        }
    }
}
