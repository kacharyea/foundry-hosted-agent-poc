using FoundryHostedAgent.Tools;

namespace FoundryHostedAgent.Tests;

public sealed class MicrosoftLearnMcpToolTests
{
    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public async Task Empty_query_fails_before_network_call(string query)
    {
        var tool = new MicrosoftLearnMcpTool(new("https://unreachable.invalid/mcp"), TimeSpan.FromMilliseconds(10));

        var result = await tool.SearchAsync(query);

        Assert.Contains("invalid_query", result, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Connection_failure_returns_controlled_error()
    {
        var tool = new MicrosoftLearnMcpTool(new("https://127.0.0.1:1/mcp"), TimeSpan.FromMilliseconds(250));

        var result = await tool.SearchAsync("Azure managed identity");

        Assert.True(
            result.Contains("mcp_unavailable", StringComparison.Ordinal) ||
            result.Contains("mcp_timeout", StringComparison.Ordinal), result);
    }
}
