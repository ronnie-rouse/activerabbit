# PR: GitLab PR Service Support

## Overview
Adds support for creating merge requests (MRs) in GitLab repositories, alongside existing GitHub pull request functionality. This enables users to choose between GitHub and GitLab for their Git provider.

## Changes

### New Files
- `app/services/gitlab_pr_service.rb` - Service for creating GitLab merge requests

### Modified Files
- `app/controllers/application_controller.rb` - Added `git_pr_service_for` helper method to dynamically select GitHub or GitLab service
- `app/controllers/errors_controller.rb` - Updated to use `git_pr_service_for` instead of hardcoded `GithubPrService`
- `app/controllers/performance_controller.rb` - Updated to use `git_pr_service_for` for both PR creation methods

## Features

### GitLab Merge Request Creation
- Creates merge requests in GitLab repositories
- Supports custom GitLab host (self-hosted instances)
- Uses GitLab API v4 for MR creation
- Handles authentication via personal access tokens

### Provider Abstraction
- `git_pr_service_for(project)` helper method automatically selects the correct service based on project settings
- Supports both GitHub and GitLab providers
- Falls back to GitHub if no provider is specified

## Usage

### Configuration
Projects must have GitLab settings configured:
- `gitlab_repo` - Repository path (e.g., `group/project`)
- `gitlab_token` - Personal access token with `api` scope
- `gitlab_host` - Optional, defaults to `https://gitlab.com`

### Creating Merge Requests
The service automatically creates MRs when:
- Creating a PR for an error issue
- Creating performance optimization PRs
- Creating N+1 query fix PRs

## Testing

### Manual Testing
1. Configure a project with GitLab settings
2. Create an error issue
3. Click "Create PR" - should create a GitLab MR instead of GitHub PR
4. Verify MR appears in GitLab with correct branch and description

### Test Cases
- [ ] MR creation with default GitLab.com host
- [ ] MR creation with custom GitLab host
- [ ] Error handling for invalid tokens
- [ ] Error handling for non-existent repositories
- [ ] Fallback to GitHub when GitLab not configured

## Dependencies
- Requires GitLab provider to be selected in project settings (see `feature/git-provider-abstraction` PR)
- Uses existing `GithubPrService` pattern for consistency

## Related PRs
- `feature/git-provider-abstraction` - Adds UI for selecting Git provider

