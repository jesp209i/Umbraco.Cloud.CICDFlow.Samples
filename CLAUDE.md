# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains sample CI/CD pipeline scripts and workflow configurations for the Umbraco Cloud CI/CD Flow feature. The scripts interact with the Umbraco Cloud API to automate deployments.

**Use V2 scripts for new implementations.** V1 scripts are deprecated but remain available.

## Architecture

### Directory Structure
- `V2/` - Current recommended scripts (V2 API endpoints)
- `V1/` - Legacy scripts (V1 API endpoints, deprecated)

Within each version:
- `bash/` - Shell scripts for Linux/macOS runners
- `powershell/` - PowerShell scripts for Windows/cross-platform
- `*/github/` - GitHub Actions workflow files (`.yml`)
- `*/azuredevops/` - Azure DevOps pipeline definitions

### CI/CD Flow Stages

The pipeline follows three sequential stages:

1. **cloud-sync** - Syncs changes from Umbraco Cloud to local repo
   - Gets latest deployment ID
   - Downloads git patch if changes exist
   - Applies patch and commits back

2. **cloud-artifact** - Packages and uploads deployment artifact
   - Creates zip of project (respecting `cloud.zipignore`)
   - Uploads to Umbraco Cloud API, receives `artifactId`

3. **cloud-deployment** - Triggers deployment to target environment
   - Starts deployment with artifact
   - Polls for completion status

### Key Scripts (V2 Bash)

| Script | Purpose |
|--------|---------|
| `get_latest_deployment.sh` | Get latest deployment ID for environment |
| `get_changes_by_id.sh` | Download git patch of cloud changes |
| `apply_patch.sh` | Apply git patch and commit |
| `upload_artifact.sh` | Upload deployment zip to cloud |
| `start_deployment.sh` | Start deployment to environment |
| `get_deployment_status.sh` | Poll deployment status |

### Required Secrets/Variables

- `PROJECT_ID` - Umbraco Cloud project ID
- `UMBRACO_CLOUD_API_KEY` - API key for authentication
- `TARGET_ENVIRONMENT_ALIAS` - Environment to deploy to (e.g., "Development", "Live")

### API Base URL

All scripts default to `https://api.cloud.umbraco.com` but accept an optional base URL parameter.

## Script Conventions

- Scripts support both `GITHUB` and `AZUREDEVOPS` pipeline vendors via parameter
- GitHub outputs use `>> "$GITHUB_OUTPUT"` syntax
- Azure DevOps outputs use `##vso[task.setvariable ...]` syntax
- All scripts return proper exit codes (0 success, 1 failure)

## Files for End Users

When integrating into a project:
- Copy workflow files to `.github/workflows/` (GitHub) or root (Azure DevOps)
- Copy scripts to `.github/scripts/` (Bash) or `.github/powershell/` (PowerShell)
- Copy `cloud.zipignore` to repository root
- Create `cloud.gitignore` from project's `.gitignore`
