using Microsoft.AspNetCore.Mvc;

namespace XYDataLabs.OrderProcessingSystem.API.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class OrderController : ControllerBase
    {
        // Example route
        [HttpGet("{id}")]
        public IActionResult Get(int id)
        {
            return Ok(new { message = "Order details" });
        }
    }
}
