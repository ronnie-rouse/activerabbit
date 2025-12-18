# PR: Fizzy Integration for Error Event Syncing

## Overview
Adds integration with Fizzy for syncing error events and issues. Enables automatic synchronization of ActiveRabbit errors to Fizzy for enhanced error tracking and management.

## Changes

### New Files
- `app/services/fizzy_sync_service.rb` - Service for syncing errors and issues to Fizzy
- `app/jobs/fizzy_batch_sync_job.rb` - Background job for batch syncing errors

### Modified Files
- `app/models/event.rb` - Added Fizzy sync methods (`sync_to_fizzy`, `fizzy_synced?`)
- `app/models/project.rb` - Added Fizzy configuration methods (`fizzy_configured?`, `fizzy_endpoint_url`, `fizzy_api_key`)
- `app/jobs/error_ingest_job.rb` - Integrated Fizzy sync into error ingestion pipeline
- `config/routes.rb` - Added routes for testing Fizzy sync and syncing all errors
- `Procfile.dev` - Added Fizzy batch sync job

## Features

### Fizzy Sync Service
- Syncs individual errors to Fizzy
- Syncs issues (error groups) to Fizzy
- Batch syncing for multiple errors
- Connection testing
- Error handling and retry logic

### Background Processing
- `FizzyBatchSyncJob` for async batch syncing
- Prevents timeouts on large error sets
- Queue management via Sidekiq

### Automatic Sync
- Errors are automatically synced to Fizzy when ingested (if configured)
- Configurable per-project
- Can be enabled/disabled via project settings

## Usage

### Configuration
Projects must have Fizzy settings configured:
- `fizzy_endpoint_url` - Fizzy API endpoint
- `fizzy_api_key` - API key for authentication
- `fizzy_sync_enabled` - Enable/disable automatic syncing

### Manual Sync
- Test connection: `POST /projects/:project_slug/settings/test_fizzy_sync`
- Sync all errors: `POST /projects/:project_slug/settings/sync_all_errors`
- Sync single error: Automatically on error creation (if enabled)

## Testing

### Manual Testing
1. Configure Fizzy endpoint and API key in project settings
2. Test connection via project settings UI
3. Create a test error and verify it syncs to Fizzy
4. Use batch sync to sync all existing errors

### Test Cases
- [ ] Connection testing with valid credentials
- [ ] Connection testing with invalid credentials
- [ ] Single error sync on creation
- [ ] Batch error sync
- [ ] Error handling for API failures
- [ ] Retry logic for transient failures

## Dependencies
- Requires Fizzy API access
- Uses Sidekiq for background job processing
- Integrates with existing error ingestion pipeline

## Related Documentation
- See project settings UI for Fizzy configuration options

