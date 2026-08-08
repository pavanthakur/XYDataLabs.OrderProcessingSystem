using XYDataLabs.OrderProcessingSystem.Domain.Entities;

namespace XYDataLabs.OrderProcessingSystem.Functions;

internal sealed record DlqReplayState(
    DlqReplayRequest Request,
    DlqQuarantineRecord Quarantine);
