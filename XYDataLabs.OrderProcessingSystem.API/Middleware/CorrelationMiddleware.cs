// Moved to SharedKernel.Observability for reuse across API and UI.
// This file re-exports the type so existing 'using API.Middleware' references still compile.
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

namespace XYDataLabs.OrderProcessingSystem.API.Middleware;

// Type alias not possible in C# — the canonical type lives in SharedKernel.Observability.CorrelationMiddleware.
// API Program.cs now references the SharedKernel type directly.
