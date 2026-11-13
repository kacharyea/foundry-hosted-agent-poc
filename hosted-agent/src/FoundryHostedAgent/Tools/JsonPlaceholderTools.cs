using System.ComponentModel;
using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;

namespace FoundryHostedAgent.Tools;

public sealed class JsonPlaceholderTools(HttpClient httpClient)
{
    public static readonly ActivitySource ActivitySource = new("FoundryHostedAgent.Tools");
    private const int MinimumUserId = 1;
    private const int MaximumUserId = 10;

    public async Task<string> GetUserDetailsAsync(
        [Description("Synthetic JSONPlaceholder user ID from 1 through 10.")] int userId,
        CancellationToken cancellationToken = default)
    {
        const string tool = "get_user_details";
        using var activity = Start(tool, userId);
        if (!ValidUserId(userId)) return InvalidUser(tool, activity);
        try
        {
            using var response = await httpClient.GetAsync($"users/{userId}", cancellationToken);
            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                FailActivity(activity, "user_not_found", response.StatusCode);
                return ToolResult<JsonPlaceholderUser>.Fail(tool, "user_not_found", "The synthetic user was not found.");
            }
            if (!response.IsSuccessStatusCode)
            {
                FailActivity(activity, "rest_rejected", response.StatusCode);
                return Upstream<JsonPlaceholderUser>(tool, response.StatusCode);
            }

            var user = await response.Content.ReadFromJsonAsync<JsonPlaceholderUser>(cancellationToken);
            if (user is null)
            {
                FailActivity(activity, "invalid_response");
                return ToolResult<JsonPlaceholderUser>.Fail(tool, "invalid_response", "The REST API returned an empty user response.");
            }
            activity?.SetStatus(ActivityStatusCode.Ok);
            return ToolResult<JsonPlaceholderUser>.Ok(tool, user);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            activity?.SetStatus(ActivityStatusCode.Error, "timeout");
            return ToolResult<JsonPlaceholderUser>.Fail(tool, "rest_timeout", "The REST API timed out.");
        }
        catch (HttpRequestException)
        {
            activity?.SetStatus(ActivityStatusCode.Error, "connection_failure");
            return ToolResult<JsonPlaceholderUser>.Fail(tool, "rest_unavailable", "The REST API is unavailable.");
        }
    }

    public async Task<string> GetUserTasksAsync(
        [Description("Synthetic JSONPlaceholder user ID from 1 through 10.")] int userId,
        [Description("True to return only tasks whose completed property is false.")] bool incompleteOnly = false,
        CancellationToken cancellationToken = default)
    {
        const string tool = "get_user_tasks";
        using var activity = Start(tool, userId);
        if (!ValidUserId(userId)) return InvalidUser<TaskToolData>(tool, activity);
        try
        {
            using var response = await httpClient.GetAsync($"todos?userId={userId}", cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                FailActivity(activity, "rest_rejected", response.StatusCode);
                return Upstream<TaskToolData>(tool, response.StatusCode);
            }

            var tasks = await response.Content.ReadFromJsonAsync<List<JsonPlaceholderTodo>>(cancellationToken) ?? [];
            if (incompleteOnly) tasks = tasks.Where(task => !task.Completed).ToList();
            activity?.SetTag("tool.result_count", tasks.Count);
            activity?.SetStatus(ActivityStatusCode.Ok);
            return ToolResult<TaskToolData>.Ok(tool, new(userId, incompleteOnly, tasks.Count, tasks));
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            activity?.SetStatus(ActivityStatusCode.Error, "timeout");
            return ToolResult<TaskToolData>.Fail(tool, "rest_timeout", "The REST API timed out.");
        }
        catch (HttpRequestException)
        {
            activity?.SetStatus(ActivityStatusCode.Error, "connection_failure");
            return ToolResult<TaskToolData>.Fail(tool, "rest_unavailable", "The REST API is unavailable.");
        }
    }

    public async Task<string> GetUserPostsAsync(
        [Description("Synthetic JSONPlaceholder user ID from 1 through 10.")] int userId,
        CancellationToken cancellationToken = default)
    {
        const string tool = "get_user_posts";
        using var activity = Start(tool, userId);
        if (!ValidUserId(userId)) return InvalidUser<PostToolData>(tool, activity);
        try
        {
            using var response = await httpClient.GetAsync($"posts?userId={userId}", cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                FailActivity(activity, "rest_rejected", response.StatusCode);
                return Upstream<PostToolData>(tool, response.StatusCode);
            }

            var posts = await response.Content.ReadFromJsonAsync<List<JsonPlaceholderPost>>(cancellationToken) ?? [];
            activity?.SetTag("tool.result_count", posts.Count);
            activity?.SetStatus(ActivityStatusCode.Ok);
            return ToolResult<PostToolData>.Ok(tool, new(userId, posts.Count, posts));
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            activity?.SetStatus(ActivityStatusCode.Error, "timeout");
            return ToolResult<PostToolData>.Fail(tool, "rest_timeout", "The REST API timed out.");
        }
        catch (HttpRequestException)
        {
            activity?.SetStatus(ActivityStatusCode.Error, "connection_failure");
            return ToolResult<PostToolData>.Fail(tool, "rest_unavailable", "The REST API is unavailable.");
        }
    }

    private static Activity? Start(string tool, int userId)
    {
        var activity = ActivitySource.StartActivity($"tool.{tool}", ActivityKind.Client);
        activity?.SetTag("gen_ai.tool.name", tool);
        activity?.SetTag("poc.synthetic_user_id", userId);
        return activity;
    }

    private static bool ValidUserId(int userId) => userId is >= MinimumUserId and <= MaximumUserId;

    private static string InvalidUser(string tool, Activity? activity) =>
        InvalidUser<JsonPlaceholderUser>(tool, activity);

    private static string InvalidUser<T>(string tool, Activity? activity)
    {
        FailActivity(activity, "invalid_user_id");
        return ToolResult<T>.Fail(tool, "invalid_user_id", "User ID must be between 1 and 10 for this synthetic API.");
    }

    private static string Upstream<T>(string tool, HttpStatusCode status) =>
        ToolResult<T>.Fail(tool, "rest_rejected", $"The REST API returned HTTP {(int)status}.");

    private static void FailActivity(Activity? activity, string errorType, HttpStatusCode? status = null)
    {
        activity?.SetTag("error.type", errorType);
        if (status.HasValue) activity?.SetTag("http.response.status_code", (int)status.Value);
        activity?.SetStatus(ActivityStatusCode.Error, errorType);
    }
}
