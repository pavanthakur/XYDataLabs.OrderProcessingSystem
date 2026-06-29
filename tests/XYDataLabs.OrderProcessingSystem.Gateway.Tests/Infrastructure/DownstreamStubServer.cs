using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace XYDataLabs.OrderProcessingSystem.Gateway.Tests.Infrastructure;

internal sealed class DownstreamStubServer : IAsyncDisposable
{
    private readonly TcpListener _listener;
    private readonly CancellationTokenSource _cancellationTokenSource = new();
    private readonly Task _runLoop;

    public Uri BaseAddress { get; }

    private DownstreamStubServer(int port)
    {
        _listener = new TcpListener(System.Net.IPAddress.Loopback, port);
        _listener.Start();
        var localEndpoint = (System.Net.IPEndPoint)_listener.LocalEndpoint;
        BaseAddress = new Uri($"http://localhost:{localEndpoint.Port}/");
        _runLoop = Task.Run(RunAsync);
    }

    public static Task<DownstreamStubServer> StartAsync()
    {
        var port = 0;
        var server = new DownstreamStubServer(port);
        return WaitUntilReadyAsync(server);
    }

    private static async Task<DownstreamStubServer> WaitUntilReadyAsync(DownstreamStubServer server)
    {
        for (var attempt = 0; attempt < 20; attempt++)
        {
            if (await CanConnectAsync(server.BaseAddress))
            {
                return server;
            }

            await Task.Delay(50);
        }

        return server;
    }

    private static async Task<bool> CanConnectAsync(Uri baseAddress)
    {
        try
        {
            using var client = new TcpClient();
            await client.ConnectAsync(baseAddress.Host, baseAddress.Port);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private async Task RunAsync()
    {
        while (!_cancellationTokenSource.IsCancellationRequested)
        {
            TcpClient? client = null;
            try
            {
                client = await _listener.AcceptTcpClientAsync(_cancellationTokenSource.Token);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (ObjectDisposedException)
            {
                break;
            }

            if (client is not null)
            {
                _ = Task.Run(() => HandleClientAsync(client));
            }
        }
    }

    private static async Task HandleClientAsync(TcpClient client)
    {
        using var _ = client;
        using var stream = client.GetStream();
        using var reader = new StreamReader(stream, Encoding.ASCII, leaveOpen: true);

        var requestLine = await reader.ReadLineAsync();
        if (string.IsNullOrWhiteSpace(requestLine))
        {
            return;
        }

        var requestParts = requestLine.Split(' ', 3, StringSplitOptions.RemoveEmptyEntries);
        var method = requestParts[0];
        var path = requestParts.Length > 1 ? requestParts[1] : "/";
        var correlationId = string.Empty;

        string? headerLine;
        while (!string.IsNullOrEmpty(headerLine = await reader.ReadLineAsync()))
        {
            var separatorIndex = headerLine.IndexOf(':');
            if (separatorIndex <= 0)
            {
                continue;
            }

            var headerName = headerLine[..separatorIndex].Trim();
            if (!headerName.Equals("X-Correlation-Id", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            correlationId = headerLine[(separatorIndex + 1)..].Trim();
        }

        var statusLine = method == "GET" ? "HTTP/1.1 200 OK" : "HTTP/1.1 405 Method Not Allowed";
        var body = method == "GET"
            ? JsonSerializer.Serialize(new
            {
                Path = path,
                Method = method,
                CorrelationId = correlationId
            })
            : string.Empty;

        var bodyBytes = Encoding.UTF8.GetBytes(body);
        var response = new StringBuilder()
            .AppendLine(statusLine)
            .AppendLine("Content-Type: application/json")
            .AppendLine($"Content-Length: {bodyBytes.Length}")
            .AppendLine("Connection: close")
            .AppendLine();

        var headerBytes = Encoding.ASCII.GetBytes(response.ToString());
        await stream.WriteAsync(headerBytes);
        if (bodyBytes.Length > 0)
        {
            await stream.WriteAsync(bodyBytes);
        }
        await stream.FlushAsync();
    }

    public async ValueTask DisposeAsync()
    {
        await _cancellationTokenSource.CancelAsync();
        _listener.Stop();

        try
        {
            await _runLoop;
        }
        catch
        {
            // Ignore shutdown race during test teardown.
        }

        _cancellationTokenSource.Dispose();
    }
}
