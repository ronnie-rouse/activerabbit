# PR: Git Provider Abstraction and Project Settings UI

## Overview
Adds support for selecting and configuring multiple Git providers (GitHub and GitLab) in project settings. Provides a unified UI for managing Git repository connections regardless of provider.

## Changes

### Modified Files
- `app/controllers/project_settings_controller.rb` - Added `update_git_settings` method supporting both GitHub and GitLab
- `app/views/project_settings/show.html.erb` - Updated UI to show provider-specific fields dynamically
- `app/views/errors/show.html.erb` - Updated to show provider-appropriate labels and icons

## Features

### Provider Selection
- Dropdown to select Git provider (GitHub or GitLab)
- Dynamic form fields based on selected provider
- Automatic clearing of unused provider settings when switching

### GitHub Configuration
- Repository path
- Installation ID (for GitHub Apps)
- Personal Access Token
- GitHub App ID and Private Key

### GitLab Configuration
- Repository path (group/project format)
- Personal Access Token
- Custom GitLab host (for self-hosted instances)

### UI Improvements
- Provider-specific labels ("Connect GitHub" vs "Connect GitLab")
- Provider-specific icons (GitHub octocat vs GitLab logo)
- Dynamic form validation
- Clear visual indication of current provider

## Usage

### Configuration Flow
1. Navigate to Project Settings
2. Select Git provider (GitHub or GitLab)
3. Fill in provider-specific fields
4. Save settings

### Switching Providers
- Changing provider automatically clears settings from the previous provider
- Previous provider's settings are preserved but not used
- Can switch back and forth without losing configuration

## Testing

### Manual Testing
1. Configure GitHub provider with repository
2. Switch to GitLab provider - GitHub fields should hide, GitLab fields should show
3. Configure GitLab provider
4. Switch back to GitHub - verify GitHub settings are preserved
5. Create a PR/MR - verify correct provider is used

### Test Cases
- [ ] GitHub provider configuration
- [ ] GitLab provider configuration
- [ ] Switching between providers
- [ ] Settings persistence when switching
- [ ] Form validation for each provider
- [ ] UI updates based on provider selection

## Dependencies
- Requires `feature/gitlab-pr-service` PR for GitLab MR creation
- Works with existing GitHub PR functionality

## Related PRs
- `feature/gitlab-pr-service` - Implements GitLab MR creation
- `feature/honeybadger-integration` - May add additional provider options in future

