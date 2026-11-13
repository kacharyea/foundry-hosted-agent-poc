# Hosted Agent application pipeline

The repository-root `azure-pipelines.yml` extends `hosted-agent/pipelines/pipeline.yml`.

The pipeline validates .NET code, builds an immutable ACR image, deploys and smoke-tests a
development agent, requires production approval, then promotes the exact image to production.
Credentials come from a federated Azure service connection and Azure DevOps variable group; no
credential belongs in this folder.
