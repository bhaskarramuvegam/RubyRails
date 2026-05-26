# Redmine Parent to Child Update Plugin - Project Overview

## Plugin Name
Redmine Parent to Child Update Plugin (v1.0.0)

## Purpose
This plugin enhances Redmine's issue management workflow by providing an interactive popup dialog that asks users if they want to create child issues when creating parent issues. It automatically replicates parent issue fields to child issues, maintaining consistency and reducing manual data entry.

## Key Requirements Met

✓ **Popup Dialog on Parent Creation**: When creating a new issue (e.g., CR/Bug/Feature), a popup appears asking "Create child? Yes or No"

✓ **Field Replication**: If "Yes", all relevant parent fields are replicated to the child issue:
  - Priority, Assigned To, Category, Target Version
  - Description (with parent reference), Due Date, Start Date
  - Estimated Hours, and Custom Fields

✓ **Recursive Application**: The dialog applies to every sub-child creation as well

✓ **Selective Parent Types**: Only configured issue types trigger the dialog (configurable in settings)

✓ **Manual Only Path**: Users can select "No" to create only the parent issue without child

## Architecture

### File Structure

```
redmine_parent_to_child_update/
├── init.rb                                    # Plugin initialization
├── README.rdoc                               # Plugin documentation
├── config/
│   ├── locales/
│   │   └── en.yml                           # i18n translations
│   └── routes.rb                            # API routes
├── lib/
│   └── redmine_parent_to_child_update/
│       ├── issue_patch.rb                   # Issue model patch for field logic
│       └── hooks.rb                         # View hooks for dialog UI
├── app/
│   ├── controllers/
│   │   └── redmine_parent_to_child_update/
│   │       └── child_issues_controller.rb   # API endpoints
│   └── views/
│       └── settings/
│           └── _redmine_parent_to_child_update_settings.html.erb  # Settings view
```

### Core Components

#### 1. **Issue Model Patch** (`issue_patch.rb`)
Extends the Issue model with methods for:
- Checking if child popup should be shown
- Replicating parent fields to child
- Tracking parent-to-child relationship
- Retrieving available child trackers

#### 2. **View Hooks** (`hooks.rb`)
Provides:
- HTML/CSS for the popup modal dialog
- JavaScript for dialog interaction and form submission
- After-save hook to create child issues
- Field replication logic

#### 3. **Child Issues Controller** (`child_issues_controller.rb`)
RESTful API endpoints for:
- Getting available trackers for child creation
- Creating child issues programmatically
- Listing child issues of a parent

#### 4. **Plugin Initialization** (`init.rb`)
- Registers the plugin with Redmine
- Configures plugin settings
- Loads patches and hooks

## Configuration

The plugin is configurable via Administration > Plugins > Parent to Child Update Plugin:

| Setting | Type | Default | Purpose |
|---------|------|---------|---------|
| enabled | boolean | true | Enable/disable plugin |
| enable_logging | boolean | true | Debug logging in Rails log |
| auto_replicate_fields | boolean | true | Auto-replicate parent fields |
| parent_issue_types | string | Bug,Feature,Task,Support | Issue types triggering dialog |

## User Workflow

### Scenario 1: Create Parent with Child
1. User creates new Bug/Feature/Task/Support issue
2. Popup appears: "Would you like to create a child issue?"
3. User clicks "Yes, Create Child"
4. Second popup shows available child issue types
5. User selects type (e.g., User Story) and enters subject
6. User clicks "Create"
7. Parent issue created, then child issue created with replicated fields
8. Child inherits: Priority, Assigned To, Category, Target Version, Due Date, etc.

### Scenario 2: Create Parent Only
1. User creates new issue
2. Popup appears
3. User clicks "No, Create [Type] Only"
4. Only parent issue is created
5. No child issue created

### Scenario 3: Create Sub-Child
1. User creates new issue (which is itself a child of another issue)
2. If child's issue type matches configured parent types, popup appears again
3. Process repeats recursively

## Field Replication Logic

When creating a child issue, these fields are automatically copied from parent:

```ruby
{
  'priority_id' => parent.priority_id,
  'assigned_to_id' => parent.assigned_to_id,
  'category_id' => parent.category_id,
  'fixed_version_id' => parent.fixed_version_id,
  'description' => "[Child of Issue #{parent.id}]\n\n" + parent.description,
  'due_date' => parent.due_date,
  'start_date' => parent.start_date,
  'estimated_hours' => parent.estimated_hours,
  'parent_issue_id' => parent.id  # Establishes parent-child relationship
}
```

Plus all custom fields that exist on the parent.

## Dialog UI

### First Dialog (Child Creation Decision)
- Title: "Create Child Issue"
- Question: "Would you like to create a child issue (e.g., User Story) for this [IssueType]?"
- Buttons: "Yes, Create Child" | "No, Create [IssueType] Only"

### Second Dialog (Child Details)
- Dropdown: Select issue type for child
- Input: Enter subject for child issue
- Buttons: "Create" | "Cancel"

## Logging

When debug logging is enabled, all operations are logged:

```
Parent to Child: Creating child issue for parent #123
Parent to Child: Replicating fields from parent issue #123 to child
  Field priority_id: 2
  Field assigned_to_id: 5
  ...
Parent to Child: Successfully created child issue #124
```

## Security

- User permissions are checked before child creation
- Users must have "Add Issues" permission in the project
- API endpoints require proper authentication
- CSRF protection is maintained

## API Endpoints

### Get Available Child Trackers
```
GET /redmine_parent_to_child_update/child_issues/trackers/:issue_id
Returns: [{ id: 1, name: 'User Story' }, ...]
```

### Create Child Issue
```
POST /redmine_parent_to_child_update/child_issues/create/:issue_id
Params:
  - tracker_id: Child tracker ID
  - subject: Child issue subject
  - description: (optional) Child issue description
Returns: { id: 124, subject: '...', url: '/issues/124' }
```

### List Child Issues
```
GET /redmine_parent_to_child_update/child_issues/children/:issue_id
Returns: [{ id: 124, subject: '...', status: 'New', tracker: 'User Story' }, ...]
```

## Testing

The plugin can be tested by:

1. Enabling the plugin in Redmine administration
2. Navigating to create a new issue of a configured type
3. Verifying the popup appears
4. Testing "Yes" path: creating child with field replication
5. Testing "No" path: creating only parent
6. Testing recursive creation: creating child of child

## Future Enhancements

Potential improvements for future versions:

1. Custom field mapping configuration
2. Automatic workflow state transitions for children
3. Bulk child creation
4. Child issue templates
5. Workflow validation before child creation
6. Email notifications on child creation
7. Time tracking inheritance
8. Activity feed integration

## Troubleshooting

### Popup doesn't appear
- Verify plugin is enabled in Administration > Plugins
- Check that issue type matches configured parent types
- Check browser console for JavaScript errors

### Fields not replicated
- Enable debug logging in plugin settings
- Check Rails log for replication errors
- Verify custom fields are properly defined

### Child not created
- Check user permissions (must have Add Issues)
- Check project is active
- Review error messages in popup dialog
- Check Rails log for detailed errors

---

**Version**: 1.0.0  
**Status**: Production Ready  
**Last Updated**: 2026-05-24
