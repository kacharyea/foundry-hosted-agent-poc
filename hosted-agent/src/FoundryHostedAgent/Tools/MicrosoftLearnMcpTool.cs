using System.ComponentModel;
using System.Diagnostics;
using System.Text.Json;
using ModelContextProtocol.Client;

namespace FoundryHostedAgent.Tools;

public sealed class MicrosoftLearnMcpTool(Uri endpoint, TimeSpan timeout)
{
    private const string ToolName = "microsoft_docs_search";
    private const int MaximumResults = 5;
    private const int MaximumExcerptCharacters = 1200;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<string> SearchAsync(
        [Description("A focused query about a Microsoft product, Azure service, or Microsoft development technology.")] string query,
        CancellationToken cancellationToken = default)
    {
        using var activity = JsonPlaceholderTools.ActivitySource.StartActivity($"tool.{ToolName}", ActivityKind.Client);
        activity?.SetTag("gen_ai.tool.name", ToolName);
        activity?.SetTag("server.address", endpoint.Host);
        if (string.IsNullOrWhiteSpace(query) || query.Length > 500)
        {
            activity?.SetTag("error.type", "invalid_query");
            activity?.SetStatus(ActivityStatusCode.Error, "invalid_query");
            return ToolResult<object>.Fail(ToolName, "invalid_query", "The documentation query must contain 1 through 500 characters.");
        }

        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(timeout);
        try
        {
            await using var client = await McpClient.CreateAsync(new HttpClientTransport(new()
            {
                Endpoint = endpoint,
                Name = "Microsoft Learn"
            }), cancellationToken: timeoutSource.Token);

            var tools = await client.ListToolsAsync(cancellationToken: timeoutSource.Token);
            if (!tools.Any(tool => string.Equals(tool.Name, ToolName, StringComparison.Ordinal)))
            {
                activity?.SetTag("error.type", "mcp_tool_missing");
                activity?.SetStatus(ActivityStatusCode.Error, "mcp_tool_missing");
                return ToolResult<object>.Fail(ToolName, "mcp_tool_missing", "Microsoft Learn MCP did not advertise microsoft_docs_search.");
            }

            var result = await client.CallToolAsync(
                ToolName,
                new Dictionary<string, object?> { ["query"] = query },
                cancellationToken: timeoutSource.Token);

            var documents = ReadBoundedResults(JsonSerializer.SerializeToElement(result, JsonOptions));
            if (documents.Count == 0)
            {
                activity?.SetTag("error.type", "mcp_invalid_response");
                activity?.SetStatus(ActivityStatusCode.Error, "mcp_invalid_response");
                return ToolResult<DocumentationSearchData>.Fail(
                    ToolName, "mcp_invalid_response", "Microsoft Learn MCP returned no readable documentation results.");
            }
            activity?.SetTag("tool.result_count", documents.Count);
            activity?.SetStatus(ActivityStatusCode.Ok);
            return ToolResult<DocumentationSearchData>.Ok(
                ToolName, new(query, documents.Count, documents));
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            activity?.SetStatus(ActivityStatusCode.Error, "timeout");
            return ToolResult<object>.Fail(ToolName, "mcp_timeout", "Microsoft Learn MCP timed out.");
        }
        catch (Exception exception) when (exception is HttpRequestException or InvalidOperationException or JsonException)
        {
            activity?.SetStatus(ActivityStatusCode.Error, "connection_failure");
            return ToolResult<object>.Fail(ToolName, "mcp_unavailable", "Microsoft Learn MCP is unavailable or returned an invalid response.");
        }
    }

    private static IReadOnlyList<DocumentationResult> ReadBoundedResults(JsonElement result)
    {
        if (!result.TryGetProperty("structuredContent", out var structured) ||
            !structured.TryGetProperty("results", out var results) ||
            results.ValueKind != JsonValueKind.Array)
            return [];

        var documents = new List<DocumentationResult>();
        foreach (var item in results.EnumerateArray().Take(MaximumResults))
        {
            var title = ReadString(item, "title");
            var url = ReadString(item, "contentUrl");
            var content = ReadString(item, "content");
            if (title is null || url is null || content is null) continue;
            documents.Add(new(title, url, content.Length <= MaximumExcerptCharacters
                ? content
                : content[..MaximumExcerptCharacters] + "…"));
        }
        return documents;
    }

    private static string? ReadString(JsonElement element, string property) =>
        element.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;
}

public sealed record DocumentationSearchData(
    string Query,
    int Count,
    IReadOnlyList<DocumentationResult> Results);

public sealed record DocumentationResult(string Title, string Url, string Excerpt);
