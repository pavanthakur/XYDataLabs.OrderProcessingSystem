using Microsoft.AspNetCore.Mvc;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Results;

namespace XYDataLabs.OrderProcessingSystem.Payments.API.Extensions;

public static class ResultExtensions
{
    public static ActionResult ToActionResult<T>(this Result<T> result)
    {
        if (result.IsSuccess)
        {
            return new OkObjectResult(ApiResponse<T>.Ok(result.Value));
        }

        return result.Error.Code switch
        {
            "NotFound" => new NotFoundObjectResult(ApiResponse<T>.Fail(result.Error.Description)),
            "Validation" => new BadRequestObjectResult(ApiResponse<T>.Fail(result.Error.Description)),
            "Conflict" => new ConflictObjectResult(ApiResponse<T>.Fail(result.Error.Description)),
            "Unauthorized" => new UnauthorizedObjectResult(ApiResponse<T>.Fail(result.Error.Description)),
            _ => new ObjectResult(ApiResponse<T>.Fail(result.Error.Description)) { StatusCode = 500 }
        };
    }
}
