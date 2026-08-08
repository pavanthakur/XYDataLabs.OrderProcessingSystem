using System.Security.Claims;
using FluentAssertions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Moq;
using XYDataLabs.OrderProcessingSystem.Application.Abstractions;
using XYDataLabs.OrderProcessingSystem.Orders.API.Controllers;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Controllers;

public sealed class DlqAdminControllerTests
{
    [Fact]
    public async Task ApproveAsync_ReturnsNotFound_WhenQuarantineRecordDoesNotExist()
    {
        var approvalService = new Mock<IDlqReplayApprovalService>();
        var logger = new Mock<ILogger<DlqAdminController>>();
        var quarantineId = Guid.NewGuid();

        approvalService
            .Setup(service => service.ApproveAsync(quarantineId, "operator-1", It.IsAny<CancellationToken>()))
            .ReturnsAsync((DlqReplayApprovalResult?)null);

        var controller = CreateController(approvalService.Object, logger.Object, "operator-1");

        var result = await controller.ApproveAsync(quarantineId, CancellationToken.None);

        result.Result.Should().BeOfType<NotFoundResult>();
    }

    [Fact]
    public async Task ApproveAsync_ReturnsOk_WhenApprovalSucceeds()
    {
        var approvalService = new Mock<IDlqReplayApprovalService>();
        var logger = new Mock<ILogger<DlqAdminController>>();
        var quarantineId = Guid.NewGuid();
        var approvalResult = new DlqReplayApprovalResult(
            quarantineId,
            Guid.NewGuid(),
            "Approved",
            DateTime.UtcNow,
            AlreadyApproved: false);

        approvalService
            .Setup(service => service.ApproveAsync(quarantineId, "operator-1", It.IsAny<CancellationToken>()))
            .ReturnsAsync(approvalResult);

        var controller = CreateController(approvalService.Object, logger.Object, "operator-1");

        var result = await controller.ApproveAsync(quarantineId, CancellationToken.None);

        var ok = result.Result.Should().BeOfType<OkObjectResult>().Subject;
        ok.Value.Should().BeEquivalentTo(approvalResult);
    }

    [Fact]
    public async Task ApproveAsync_UsesNameAsFallback_WhenNameIdentifierIsMissing()
    {
        var approvalService = new Mock<IDlqReplayApprovalService>();
        var logger = new Mock<ILogger<DlqAdminController>>();
        var quarantineId = Guid.NewGuid();
        var approvalResult = new DlqReplayApprovalResult(
            quarantineId,
            Guid.NewGuid(),
            "Approved",
            DateTime.UtcNow,
            AlreadyApproved: true);

        approvalService
            .Setup(service => service.ApproveAsync(quarantineId, "tenant-admin", It.IsAny<CancellationToken>()))
            .ReturnsAsync(approvalResult);

        var controller = CreateController(
            approvalService.Object,
            logger.Object,
            nameIdentifier: null,
            userName: "tenant-admin");

        var result = await controller.ApproveAsync(quarantineId, CancellationToken.None);

        result.Result.Should().BeOfType<OkObjectResult>();
        approvalService.Verify(
            service => service.ApproveAsync(quarantineId, "tenant-admin", It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public void Controller_ShouldRequirePhase10OperatorRole()
    {
        var authorizeAttribute = typeof(DlqAdminController)
            .GetCustomAttributes(typeof(AuthorizeAttribute), inherit: true)
            .OfType<AuthorizeAttribute>()
            .Single();

        authorizeAttribute.Roles.Should().Be("phase10-operator");
    }

    private static DlqAdminController CreateController(
        IDlqReplayApprovalService approvalService,
        ILogger<DlqAdminController> logger,
        string? nameIdentifier,
        string? userName = null)
    {
        var claims = new List<Claim>();
        if (!string.IsNullOrWhiteSpace(nameIdentifier))
        {
            claims.Add(new Claim(ClaimTypes.NameIdentifier, nameIdentifier));
        }

        if (!string.IsNullOrWhiteSpace(userName))
        {
            claims.Add(new Claim(ClaimTypes.Name, userName));
        }

        var controller = new DlqAdminController(approvalService, logger)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(claims, "test"))
                }
            }
        };

        return controller;
    }
}
