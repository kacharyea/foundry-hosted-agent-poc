using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Azure.Core;
using Azure.Identity;

var options = ClientOptions.FromEnvironment(args);
var credential = new DefaultAzureCredential();
AccessToken token;
try
{
    token = await credential.GetTokenAsync(
        new TokenRequestContext(["https://ai.azure.com/.default"]));
}
catch (Exception exception) when (exception is AuthenticationFailedException or CredentialUnavailableException)
{
    Console.Error.WriteLine("Authentication failed. Sign in with an approved Entra identity using 'az login'.");
    return 2;
}

using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds) };
http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
http.DefaultRequestHeaders.UserAgent.ParseAdd("FoundryHostedAgentConsoleClient/1.0");

var endpoint = new Uri(
    $"{options.ProjectEndpoint.TrimEnd('/')}/agents/{Uri.EscapeDataString(options.AgentName)}" +
    "/endpoint/protocols/openai/responses?api-version=v1");

try
{
    using var response = await http.PostAsJsonAsync(endpoint, new
    {
        input = options.Prompt,
        stream = false,
        store = true
    });
    var payload = await response.Content.ReadAsStringAsync();
    if (!response.IsSuccessStatusCode)
    {
        Console.Error.WriteLine($"Agent invocation failed with HTTP {(int)response.StatusCode}. No token or response body was logged.");
        return 3;
    }

    using var json = JsonDocument.Parse(payload);
    var text = ResponseText.Read(json.RootElement);
    Console.WriteLine(string.IsNullOrWhiteSpace(text) ? payload : text);
    return 0;
}
catch (OperationCanceledException)
{
    Console.Error.WriteLine("Agent invocation timed out.");
    return 4;
}
catch (HttpRequestException exception)
{
    Console.Error.WriteLine($"Agent endpoint is unavailable: {exception.Message}");
    return 5;
}
catch (JsonException)
{
    Console.Error.WriteLine("Agent returned an unreadable response.");
    return 6;
}

internal sealed record ClientOptions(
    string ProjectEndpoint,
    string AgentName,
    string Prompt,
    int TimeoutSeconds)
{
    public static ClientOptions FromEnvironment(string[] args)
    {
        var endpoint = Environment.GetEnvironmentVariable("FOUNDRY_PROJECT_ENDPOINT")
            ?? throw new InvalidOperationException("FOUNDRY_PROJECT_ENDPOINT is required.");
        var agentName = Environment.GetEnvironmentVariable("FOUNDRY_HOSTED_AGENT_NAME")
            ?? "foundry-hosted-integration-poc";
        var prompt = args.Length == 0
            ? "Show user 1 details and incomplete tasks."
            : string.Join(' ', args);

        if (!Uri.TryCreate(endpoint, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps ||
            !string.IsNullOrEmpty(uri.UserInfo) || !string.IsNullOrEmpty(uri.Query) ||
            !string.IsNullOrEmpty(uri.Fragment))
            throw new InvalidOperationException("FOUNDRY_PROJECT_ENDPOINT must be an absolute HTTPS URI.");
        if (agentName.Length is < 1 or > 63 || agentName.Any(character =>
                !(char.IsAsciiLetterOrDigit(character) || character == '-')))
            throw new InvalidOperationException("FOUNDRY_HOSTED_AGENT_NAME is invalid.");
        if (prompt.Length is < 1 or > 4000)
            throw new InvalidOperationException("The prompt must contain 1 through 4000 characters.");

        return new(endpoint, agentName, prompt, 90);
    }
}

internal static class ResponseText
{
    public static string Read(JsonElement root)
    {
        var values = new List<string>();
        Walk(root, values);
        return string.Join(Environment.NewLine, values.Distinct(StringComparer.Ordinal));
    }

    private static void Walk(JsonElement element, List<string> values)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            if (element.TryGetProperty("type", out var type) && type.GetString() == "output_text" &&
                element.TryGetProperty("text", out var text) && !string.IsNullOrWhiteSpace(text.GetString()))
                values.Add(text.GetString()!);
            foreach (var property in element.EnumerateObject()) Walk(property.Value, values);
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray()) Walk(item, values);
        }
    }
}
