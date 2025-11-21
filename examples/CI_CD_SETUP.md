# CI/CD Setup Guide

## Overview

This project uses GitHub Actions for automated builds and deployments. The CI/CD pipeline supports three environments: dev, stage, and production.

## Workflows

### Build and Deploy (`build-and-deploy.yml`)

**Triggers:**
- Push to `dev` branch → builds and deploys to dev environment
- Push to `main` branch → builds and deploys to stage, then production (with approval)

**Stages:**
1. **Determine Target**: Extracts versions from `pubspec.yaml` files and determines build type
2. **Test**: Runs Dart and Flutter tests
3. **Build Server**: Builds Docker image and pushes to `ghcr.io/intersubjective/tentura-server`
4. **Build Web**: Builds Flutter web static files and creates `.tar.gz` archives
5. **Deploy Dev**: Deploys to dev environment (automatic)
6. **Deploy Stage**: Deploys to stage environment (automatic for main branch)
7. **Deploy Prod**: Deploys to production environment (requires manual approval)

### CI (`ci.yml`)

**Triggers:**
- Pull requests to `main` or `dev`
- Pushes to `main`

**Stages:**
1. **Test**: Runs Dart and Flutter tests
2. **Validate Builds**: Validates Docker and Flutter builds without pushing

## Required Secrets

Configure these secrets in GitHub repository settings (Settings > Secrets and variables > Actions):

### Per Environment (dev/stage/prod)

- `VPS_HOST`: Target server hostname or IP address
- `VPS_SSH_KEY`: SSH private key for deployment (must have access to deploy user)

### Shared

- `GITHUB_TOKEN`: Automatically provided by GitHub Actions (no setup needed)

## Environment Configuration

### Production Approval Gate

Production deployments require manual approval. To configure:

1. Go to **Settings > Environments**
2. Create or edit the `prod` environment
3. Under **Protection rules**, enable **Required reviewers**
4. Add repository owners or specific team members as reviewers

When a deployment to production is triggered, it will pause and wait for approval from a configured reviewer before proceeding.

## Docker Image Tagging

- **Dev branch**: Images tagged as `dev-{sha}` and `dev-latest`
- **Main branch**: Images tagged as `v{version}` and `latest`
- **Deployment**: Always uses `latest` tag in Docker Compose

## VPS Setup

### 1. Create Deployment Directory

```bash
sudo mkdir -p /opt/tentura
sudo chown deploy:deploy /opt/tentura
```

Or use user home directory:
```bash
mkdir -p ~/tentura
```

### 2. Install Deployment Script

Copy `examples/deploy.sh` to your VPS:

```bash
# On VPS
sudo cp examples/deploy.sh /opt/tentura/deploy.sh
sudo chmod +x /opt/tentura/deploy.sh
sudo chown deploy:deploy /opt/tentura/deploy.sh
```

### 3. Setup SSH Access

Ensure the SSH key used in GitHub secrets has:
- Access to the `deploy` user account
- Permissions to run Docker commands
- Access to the deployment directory

### 4. Docker Compose Setup

Ensure `compose.prod.yaml` is present in the deployment directory on the VPS.

The deployment script expects:
- `compose.prod.yaml` in the deployment directory
- `./web/` directory for static files (mounted in Docker Compose)

## Deployment Process

1. **Build**: Server Docker image and Flutter web static files are built
2. **Archive**: Web files are packaged into `.tar.gz` archives
3. **Transfer**: Archives are copied to VPS via SCP
4. **Extract**: Archives are extracted to the Docker volume mount point
5. **Update**: Docker Compose pulls latest images and restarts services

## Troubleshooting

### Build Failures

- Check that `packages/server/Dockerfile_build` references the correct entry point (`bin/tentura.dart`)
- Ensure all dependencies are properly configured in `pubspec.yaml` files

### Deployment Failures

- Verify SSH key has correct permissions and access
- Check that deployment directory exists and is writable
- Ensure Docker Compose is installed and accessible to the deploy user
- Verify `compose.prod.yaml` is present in the deployment directory

### Approval Not Working

- Ensure the `prod` environment is configured in GitHub repository settings
- Check that required reviewers are added to the environment
- Verify the workflow references the correct environment name (`prod`)

