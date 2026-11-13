FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY FoundryHostedAgent.csproj .
RUN dotnet restore FoundryHostedAgent.csproj
COPY . .
RUN dotnet publish FoundryHostedAgent.csproj -c Release -r linux-x64 --self-contained false \
    -p:PublishReadyToRun=true -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
ENV ASPNETCORE_URLS=http://+:8088 \
    DOTNET_EnableDiagnostics=0
EXPOSE 8088
COPY --from=build /app/publish .
USER $APP_UID
ENTRYPOINT ["dotnet", "foundry-hosted-integration-agent.dll"]
