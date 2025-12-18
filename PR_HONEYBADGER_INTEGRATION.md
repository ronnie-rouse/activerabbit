# PR: Honeybadger Integration for Error Imports

## Overview
Adds integration with Honeybadger for importing errors from existing Honeybadger projects. Enables users to migrate their error tracking from Honeybadger to ActiveRabbit or use both systems in parallel.

## Changes

### New Files
- `app/controllers/error_imports_controller.rb` - Controller for managing error imports
- `app/models/error_import.rb` - Model for tracking imported errors
- `app/services/error_import/base_provider.rb` - Abstract base class for error import providers
- `app/services/error_import/honeybadger_provider.rb` - Honeybadger-specific import provider
- `app/jobs/error_import_job.rb` - Background job for importing errors
- `app/jobs/error_import_webhook_job.rb` - Background job for processing Honeybadger webhooks
- `app/views/error_imports/index.html.erb` - List of error imports
- `app/views/error_imports/show.html.erb` - Detailed import view
- `db/migrate/20251217200350_create_error_imports.rb` - Migration for error_imports table
- `db/migrate/20251217200351_add_external_source_to_events.rb` - Migration for tracking external sources

### Modified Files
- `app/controllers/project_settings_controller.rb` - Added `update_import_settings` for Honeybadger configuration
- `app/controllers/webhooks_controller.rb` - Added Honeybadger webhook handling
- `app/models/event.rb` - Added `external_source` tracking
- `app/models/project.rb` - Added Honeybadger configuration methods
- `config/initializers/filter_parameter_logging.rb` - Added Honeybadger parameters to filter list
- `config/routes.rb` - Added routes for error imports and Honeybadger webhooks

## Features

### Error Import Provider System
- Extensible architecture with `BaseProvider` abstract class
- Easy to add new providers (Sentry, Rollbar, etc.)
- Consistent interface across providers

### Honeybadger Integration
- Import errors from Honeybadger projects
- Webhook support for real-time error syncing
- API-based import for historical data
- Tracks original Honeybadger error IDs

### Import Management
- View all imports for a project
- See import status and statistics
- Track which errors came from Honeybadger
- View detailed import information

### Webhook Support
- Real-time error syncing from Honeybadger
- Automatic error creation when Honeybadger receives errors
- Configurable webhook enable/disable per project

## Usage

### Configuration
Projects must have Honeybadger settings configured:
- `honeybadger_api_token` - Honeybadger API token
- `honeybadger_project_id` - Honeybadger project ID
- `honeybadger_webhook_enabled` - Enable/disable webhook syncing

### Webhook Setup
1. Configure Honeybadger API token and project ID
2. Enable webhook in project settings
3. Copy webhook URL from project settings
4. Add webhook URL in Honeybadger project settings
5. Errors will automatically sync when they occur in Honeybadger

### Manual Import
- Use `ErrorImportJob` to import historical errors
- Import specific error ranges
- Track import progress

## Testing

### Manual Testing
1. Configure Honeybadger API token and project ID
2. Enable webhook
3. Create an error in Honeybadger
4. Verify error appears in ActiveRabbit
5. Check error import list for import record
6. Verify `external_source` is set to "honeybadger"

### Test Cases
- [ ] Webhook receives errors from Honeybadger
- [ ] Errors are created correctly
- [ ] External source is tracked
- [ ] Import records are created
- [ ] API import works
- [ ] Error handling for invalid credentials
- [ ] Error handling for webhook failures

## Database Changes
- New `error_imports` table
- `events.external_source` column added
- Migrations included

## Dependencies
- Requires Honeybadger API access
- Uses Sidekiq for background job processing
- Integrates with existing error tracking system

## Security
- API tokens stored securely in project settings
- Webhook signature verification (if implemented)
- Parameter filtering for sensitive data

## Future Enhancements
- Support for other error tracking providers
- Bulk import UI
- Import scheduling
- Import status notifications

