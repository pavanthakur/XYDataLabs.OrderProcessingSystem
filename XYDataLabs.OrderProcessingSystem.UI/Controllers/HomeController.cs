using Microsoft.AspNetCore.Mvc;

namespace XYDataLabs.OrderProcessingSystem.UI.Controllers
{
    public class HomeController : Controller
    {
        public IActionResult Index()
        {
            return View();
        }
    }
}