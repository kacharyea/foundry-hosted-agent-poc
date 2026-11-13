using System.Net;
using System.Text;
using System.Text.Json;
using FoundryHostedAgent.Tools;

namespace FoundryHostedAgent.Tests;

public sealed class JsonPlaceholderToolsTests
{
    [Fact]
    public async Task User_details_calls_expected_read_only_route()
    {
        var handler = new StubHandler("""
            {"id":1,"name":"Leanne Graham","username":"Bret","email":"a@example.test",
             "address":{"street":"Kulas","suite":"Apt. 1","city":"Test","zipcode":"12345"},
             "phone":"555-0100","website":"example.test",
             "company":{"name":"Romaguera","catchPhrase":"test","bs":"test"}}
            """);
        var tools = Create(handler);

        var result = await tools.GetUserDetailsAsync(1);

        Assert.Equal(HttpMethod.Get, handler.Method);
        Assert.Equal("https://jsonplaceholder.typicode.com/users/1", handler.Uri?.ToString());
        using var json = JsonDocument.Parse(result);
        Assert.True(json.RootElement.GetProperty("success").GetBoolean());
        Assert.Equal("get_user_details", json.RootElement.GetProperty("tool").GetString());
        Assert.Equal(1, json.RootElement.GetProperty("data").GetProperty("id").GetInt32());
    }

    [Fact]
    public async Task Incomplete_tasks_are_filtered_deterministically()
    {
        var handler = new StubHandler("""
            [{"userId":1,"id":1,"title":"open","completed":false},
             {"userId":1,"id":2,"title":"done","completed":true}]
            """);
        var result = await Create(handler).GetUserTasksAsync(1, incompleteOnly: true);

        Assert.Contains("todos?userId=1", handler.Uri?.ToString(), StringComparison.Ordinal);
        using var json = JsonDocument.Parse(result);
        var data = json.RootElement.GetProperty("data");
        Assert.Equal(1, data.GetProperty("count").GetInt32());
        Assert.False(data.GetProperty("tasks")[0].GetProperty("completed").GetBoolean());
    }

    [Fact]
    public async Task Posts_return_structured_results()
    {
        var handler = new StubHandler("""[{"userId":2,"id":11,"title":"hello","body":"body"}]""");
        var result = await Create(handler).GetUserPostsAsync(2);

        using var json = JsonDocument.Parse(result);
        Assert.Equal(1, json.RootElement.GetProperty("data").GetProperty("count").GetInt32());
        Assert.Equal("get_user_posts", json.RootElement.GetProperty("tool").GetString());
    }

    [Theory]
    [InlineData(0)]
    [InlineData(11)]
    public async Task Invalid_user_id_never_calls_external_api(int userId)
    {
        var handler = new StubHandler("{}");
        var result = await Create(handler).GetUserDetailsAsync(userId);

        Assert.Equal(0, handler.CallCount);
        Assert.Contains("invalid_user_id", result, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Rest_error_is_returned_as_controlled_tool_failure()
    {
        var handler = new StubHandler("upstream details must not leak", HttpStatusCode.ServiceUnavailable);
        var result = await Create(handler).GetUserPostsAsync(1);

        Assert.Contains("rest_rejected", result, StringComparison.Ordinal);
        Assert.DoesNotContain("upstream details", result, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Rest_timeout_is_returned_as_controlled_tool_failure()
    {
        var tools = new JsonPlaceholderTools(new HttpClient(new TimeoutHandler())
        {
            BaseAddress = new("https://jsonplaceholder.typicode.com/"),
            Timeout = TimeSpan.FromMilliseconds(20)
        });

        var result = await tools.GetUserDetailsAsync(1);

        Assert.Contains("rest_timeout", result, StringComparison.Ordinal);
    }

    private static JsonPlaceholderTools Create(HttpMessageHandler handler) => new(new HttpClient(handler)
    {
        BaseAddress = new("https://jsonplaceholder.typicode.com/"),
        Timeout = TimeSpan.FromSeconds(1)
    });

    private sealed class StubHandler(string body, HttpStatusCode status = HttpStatusCode.OK) : HttpMessageHandler
    {
        public int CallCount { get; private set; }
        public HttpMethod? Method { get; private set; }
        public Uri? Uri { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            CallCount++;
            Method = request.Method;
            Uri = request.RequestUri;
            return Task.FromResult(new HttpResponseMessage(status)
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json")
            });
        }
    }

    private sealed class TimeoutHandler : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken);
            return new(HttpStatusCode.OK);
        }
    }
}
