# PR: Event Views and Display Improvements

## Overview
Adds comprehensive views for displaying events (error occurrences) with filtering, statistics, and detailed information. Improves the user experience for browsing and analyzing error events.

## Changes

### New Files
- `app/views/events/index.html.erb` - Event listing page with filters and statistics
- `app/views/events/show.html.erb` - Detailed event view with full context

### Modified Files
- `app/controllers/events_controller.rb` - Updated stats calculation and filtering logic

## Features

### Event Index Page
- List of all events with pagination
- Filtering by:
  - Environment
  - Controller/Action
  - Issue (error group)
  - Date range
- Statistics dashboard:
  - Total events today
  - Errors today
  - Performance events today
  - Average response time

### Event Detail Page
- Full event information
- Backtrace display
- Request details (method, path, headers)
- Related issue information
- Environment and release context

### Improved Statistics
- More accurate event counting
- Separate performance event metrics
- Better handling of event types

## Usage

### Viewing Events
- Navigate to `/projects/:project_slug/events` for event list
- Click any event to view details
- Use filters to narrow down events
- View statistics in the sidebar

### Filtering
- Select environment from dropdown
- Search by controller/action
- Filter by specific issue
- Use date range picker

## Testing

### Manual Testing
1. Create several error events
2. Navigate to events index page
3. Verify events are displayed correctly
4. Test each filter option
5. Click an event to view details
6. Verify statistics are accurate

### Test Cases
- [ ] Event listing displays correctly
- [ ] Pagination works
- [ ] Environment filter works
- [ ] Controller/action filter works
- [ ] Issue filter works
- [ ] Statistics are accurate
- [ ] Event detail page displays all information
- [ ] Backtrace is formatted correctly

## Dependencies
- Requires existing Event model
- Uses existing Issue associations
- Integrates with existing project structure

## UI/UX Improvements
- Clean, modern interface using Tailwind CSS
- Responsive design
- Clear visual hierarchy
- Helpful statistics at a glance

