using System.Text.Json;

namespace FoundryHostedAgent.Tools;

public sealed record ToolResult<T>(bool Success, string Tool, T? Data, ToolError? Error)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public static string Ok(string tool, T data) =>
        JsonSerializer.Serialize(new ToolResult<T>(true, tool, data, null), JsonOptions);

    public static string Fail(string tool, string code, string message) =>
        JsonSerializer.Serialize(new ToolResult<T>(false, tool, default, new(code, message)), JsonOptions);
}

public sealed record ToolError(string Code, string Message);
