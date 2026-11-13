using System.Text.Json.Serialization;

namespace FoundryHostedAgent.Tools;

public sealed record JsonPlaceholderUser(
    int Id,
    string Name,
    string Username,
    string Email,
    JsonPlaceholderAddress Address,
    string Phone,
    string Website,
    JsonPlaceholderCompany Company);

public sealed record JsonPlaceholderAddress(
    string Street,
    string Suite,
    string City,
    string Zipcode);

public sealed record JsonPlaceholderCompany(string Name, string CatchPhrase, string Bs);

public sealed record JsonPlaceholderTodo(
    int UserId,
    int Id,
    string Title,
    bool Completed);

public sealed record JsonPlaceholderPost(
    int UserId,
    int Id,
    string Title,
    string Body);

public sealed record TaskToolData(
    int UserId,
    bool IncompleteOnly,
    int Count,
    IReadOnlyList<JsonPlaceholderTodo> Tasks);

public sealed record PostToolData(
    int UserId,
    int Count,
    IReadOnlyList<JsonPlaceholderPost> Posts);
