using System.Diagnostics.Metrics;
using FluentAssertions;
using XYDataLabs.OrderProcessingSystem.SharedKernel.Observability;

namespace XYDataLabs.OrderProcessingSystem.API.Tests.Configuration;

public class BusinessMetricsTests
{
    [Fact]
    public void RecordTenantContextFailure_EmitsCounterMeasurement()
    {
        var measurements = CaptureMeasurements(() =>
            BusinessMetrics.RecordTenantContextFailure("CreateOrderCommand", hasTenantContext: false));

        var measurement = measurements.Should().ContainSingle(m =>
            m.InstrumentName == "orderprocessing.tenant_context.failures").Subject;

        measurement.Value.Should().Be(1);
        measurement.Tags.Should().ContainKey("request_name").WhoseValue.Should().Be("CreateOrderCommand");
        measurement.Tags.Should().ContainKey("tenant_context_present").WhoseValue.Should().Be("False");
    }

    [Fact]
    public void RecordProblemResponse_EmitsCounterMeasurement()
    {
        var measurements = CaptureMeasurements(() =>
            BusinessMetrics.RecordProblemResponse(400, "urn:xydatalabs:problem:validation-failed"));

        var measurement = measurements.Should().ContainSingle(m =>
            m.InstrumentName == "orderprocessing.api.problem_responses").Subject;

        measurement.Value.Should().Be(1);
        measurement.Tags.Should().ContainKey("status_code").WhoseValue.Should().Be("400");
        measurement.Tags.Should().ContainKey("problem_type").WhoseValue.Should().Be("urn:xydatalabs:problem:validation-failed");
    }

    [Fact]
    public void RecordPaymentAttempt_EmitsCounterAndHistogramMeasurements()
    {
        var measurements = CaptureMeasurements(() =>
            BusinessMetrics.RecordPaymentAttempt(
                outcome: "success",
                providerName: "OpenPay",
                isThreeDSecureEnabled: true,
                paymentStatus: "completed",
                duration: TimeSpan.FromMilliseconds(125)));

        var counter = measurements.Should().ContainSingle(m =>
            m.InstrumentName == "orderprocessing.payments.completed").Subject;
        var histogram = measurements.Should().ContainSingle(m =>
            m.InstrumentName == "orderprocessing.payments.duration").Subject;

        counter.Value.Should().Be(1);
        histogram.Value.Should().Be(125);

        foreach (var measurement in new[] { counter, histogram })
        {
            measurement.Tags.Should().ContainKey("outcome").WhoseValue.Should().Be("success");
            measurement.Tags.Should().ContainKey("provider").WhoseValue.Should().Be("OpenPay");
            measurement.Tags.Should().ContainKey("three_d_secure_enabled").WhoseValue.Should().Be("True");
            measurement.Tags.Should().ContainKey("payment_status").WhoseValue.Should().Be("completed");
        }
    }

    private static List<MetricMeasurement> CaptureMeasurements(Action action)
    {
        _ = BusinessMetrics.MeterName;

        var measurements = new List<MetricMeasurement>();
        using var listener = new MeterListener();

        listener.InstrumentPublished = (instrument, meterListener) =>
        {
            if (string.Equals(instrument.Meter.Name, BusinessMetrics.MeterName, StringComparison.Ordinal))
            {
                meterListener.EnableMeasurementEvents(instrument);
            }
        };

        listener.SetMeasurementEventCallback<long>((instrument, measurement, tags, _) =>
            measurements.Add(new MetricMeasurement(instrument.Name, measurement, ToDictionary(tags))));
        listener.SetMeasurementEventCallback<double>((instrument, measurement, tags, _) =>
            measurements.Add(new MetricMeasurement(instrument.Name, measurement, ToDictionary(tags))));
        listener.Start();

        action();

        return measurements;
    }

    private static Dictionary<string, string> ToDictionary(ReadOnlySpan<KeyValuePair<string, object?>> tags)
    {
        var dictionary = new Dictionary<string, string>(StringComparer.Ordinal);

        foreach (var tag in tags)
        {
            dictionary[tag.Key] = tag.Value?.ToString() ?? string.Empty;
        }

        return dictionary;
    }

    private sealed record MetricMeasurement(string InstrumentName, double Value, Dictionary<string, string> Tags);
}