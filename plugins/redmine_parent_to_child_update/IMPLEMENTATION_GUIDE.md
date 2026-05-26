# Redmine Parent to Child Update Plugin - Implementation Guide

## Overview

This implementation guide provides detailed instructions for integrating the Parent to Child Update Plugin with your existing Redmine instance.

## System Requirements

- **Redmine Version**: 3.0 or higher (tested with 4.x and 5.x)
- **Ruby**: 2.0 or higher
- **Rails**: 4.2 or higher
- **Database**: MySQL, PostgreSQL, or SQLite
- **Browser**: Any modern browser supporting CSS3 and ES5 JavaScript

## Architecture Overview

### How It Works

1. **Issue Creation**: User creates a new issue of a configured type (e.g., CR/Bug/Feature)
2. **Hook Trigger**: Redmine fires the `view_issues_form_details_bottom` hook
3. **Popup Display**: Plugin injects HTML/CSS/JavaScript to display dialog
4. **User Decision**: User chooses "Yes" to create child or "No" to create parent only
5. **Field Replication**: If "Yes", child issue is created with replicated parent fields
6. **Recursive Flow**: If child becomes a parent of the configured type, dialog shows again

### Component Interaction

```
Issue Creation Form
       ↓
   Hook Trigger
       ↓
   Plugin Hooks (view_issues_form_details_bottom)
       ↓
   Modal Dialog Display (HTML/CSS/JavaScript)
       ↓
   User Decision
       ├─→ "Yes" → Child Tracker Selection
       │              ↓
       │          Child Details Entry
       │              ↓
       │          Form Hidden Input Addition
       │              ↓
       │          Form Submission
       │              ↓
       │          Post-Save Hook (controller_issues_new_after_save)
       │              ↓
       │          Field Replication (issue_patch.rb)
       │              ↓
       │          Child Issue Creation
       │
       └─→ "No" → Form Submission (Parent Only)
```

## Integration Steps

### Step 1: Deploy Plugin Files

1. Copy the plugin directory to Redmine:
   ```bash
   cp -r redmine_parent_to_child_update /path/to/redmine/plugins/
   ```

2. Verify directory structure:
   ```bash
   ls -la /path/to/redmine/plugins/redmine_parent_to_child_update/
   ```

### Step 2: Load Plugin Hooks

The plugin is loaded through Redmine's plugin loading mechanism. When Redmine starts:

1. **init.rb is executed** - Registers the plugin and loads dependencies
2. **Issue model is patched** - Methods added via `Issue.send(:include, RedmineParentToChildUpdate::IssuePatch)`
3. **Hooks are registered** - `RedmineParentToChildUpdate::Hooks` hooks into Redmine's view system

### Step 3: Enable Plugin in Redmine

1. Go to **Administration** → **Plugins**
2. Find **"Parent to Child Update Plugin"** v1.0.0
3. Click plugin name to configure settings
4. Enable: "Enable Parent to Child Update Plugin"
5. Save settings

### Step 4: Configure Parent Issue Types

1. In plugin settings, find **"Parent Issue Types (comma-separated)"**
2. Enter the issue type names that should trigger the dialog:
   ```
   CR,Bug,Feature,Task,Support
   ```
3. Use exact names as they appear in **Administration → Issue Types**
4. Save settings

### Step 5: Test Deployment

1. Create a test issue with one of the configured types
2. Verify popup appears after form submission
3. Test "Yes" path: Create child with replicated fields
4. Test "No" path: Create parent only
5. Verify fields were replicated correctly

## Integration Points

### 1. Issue Model (via Patching)

The plugin patches the Issue model to add:

```ruby
# Methods added:
- parent_child_update_enabled?()
- parent_issue_types()
- replicate_fields_from_parent(parent_issue)
- should_show_child_popup?()
- available_child_trackers()

# Attributes added:
- parent_to_replicate
- replicate_parent_fields
```

### 2. View Integration (via Hooks)

The plugin hooks into:

- `view_issues_form_details_bottom` - Injects dialog HTML/CSS/JavaScript
- `controller_issues_new_after_save` - Creates child after parent saved

### 3. Routes Integration

The plugin adds these routes:

```
GET  /redmine_parent_to_child_update/child_issues/trackers/:issue_id
POST /redmine_parent_to_child_update/child_issues/create/:issue_id
GET  /redmine_parent_to_child_update/child_issues/children/:issue_id
```

## Customization Guide

### Customize Dialog Appearance

Edit `lib/redmine_parent_to_child_update/hooks.rb`, section "Add inline styles for modal":

```ruby
output << ".child-creation-modal { 
  /* Customize modal background, size, etc. */
  background-color: rgba(0,0,0,0.7);  # Change opacity
  width: 600px;                        # Change width
}"
```

### Add Additional Fields to Replicate

Edit `lib/redmine_parent_to_child_update/issue_patch.rb`, method `replicate_fields_from_parent`:

```ruby
fields_to_replicate = {
  'priority_id' => parent_issue.priority_id,
  # ... existing fields ...
  'my_custom_field' => parent_issue.my_custom_field,  # ADD THIS
}
```

### Change Default Parent Issue Types

Edit `lib/redmine_parent_to_child_update/issue_patch.rb`:

```ruby
def parent_issue_types
  types = Setting.plugin_redmine_parent_to_child_update['parent_issue_types']
  types ||= 'MyType1,MyType2,MyType3'  # Change this
  types.split(',').map(&:strip)
end
```

### Customize Localization

Edit `config/locales/en.yml` to change dialog text:

```yaml
redmine_parent_to_child_update:
  dialog:
    title: 'Custom Title'
    description: 'Custom description text'
    # ... etc
```

## Data Flow

### Creating a Parent Issue with Child

```
1. User fills issue form (Subject: "Handle payment processing")
2. User clicks "Save"
   │
3. Redmine processes form → Issue model created (not saved yet)
   │
4. Hook fires: view_issues_form_details_bottom
   │
5. Plugin injects modal HTML/CSS/JS
   │
6. JavaScript intercepts form submission, shows modal
   │
7. Modal displays: "Would you like to create a child issue?"
   │
8. User clicks "Yes, Create Child"
   │
9. Child tracker selection modal appears
   │
10. User selects tracker (e.g., "User Story")
    │
11. User enters child subject: "Add payment UI"
    │
12. User clicks "Create"
    │
13. Form submission continues with hidden inputs:
    - create_child: true
    - child_tracker_id: 3
    - child_subject: "Add payment UI"
    │
14. Parent issue created (ID #123)
    │
15. Hook fires: controller_issues_new_after_save
    │
16. Plugin reads hidden inputs
    │
17. Creates child issue with:
    - Subject: "Add payment UI"
    - Tracker: User Story
    - Parent ID: 123
    - Priority: (replicated from parent)
    - Assigned To: (replicated from parent)
    - Due Date: (replicated from parent)
    - ... other replicated fields
    │
18. Child issue created (ID #124)
    │
19. Parent issue page displays with child listed
    │
20. User sees both issues created in Redmine
```

## Database Considerations

### No Schema Changes Required

This plugin does NOT:
- Create new database tables
- Modify existing Issue schema
- Require migrations

The plugin uses existing Redmine fields and relationships.

### Parent-Child Relationships

Parent-child relationships use existing Redmine field:
- Issue `parent_id` (foreign key to Issue)

This is a native Redmine relationship, fully supported by the system.

## Security Considerations

### Permission Checks

The plugin checks permissions before:
1. Displaying child creation dialog
2. Creating child issues
3. Accessing child issue endpoints

Required permissions:
- View Issues (to see parent)
- Add Issues (to create child)

### CSRF Protection

The plugin integrates with Rails' CSRF protection:
- Form submissions include CSRF token
- API endpoints accept API tokens or session auth

### Input Validation

The plugin validates:
- Tracker ID exists
- Subject is not empty
- Parent issue exists
- User can access project

## Performance Implications

### Client-Side Performance
- Modal dialog: Lightweight CSS + JavaScript (~5KB)
- No impact on issue loading

### Server-Side Performance
- Dialog injection: Minimal overhead (~1ms)
- Child creation: One additional issue save (~50-100ms)

### Database Performance
- No additional queries for dialog display
- One additional INSERT for child issue creation
- No impact on existing issue operations

## Logging and Debugging

### Enable Debug Logging

In plugin settings:
1. Check "Enable Debug Logging"
2. Check Rails log file

### Log Locations

```bash
# Production
/path/to/redmine/log/production.log

# Development
/path/to/redmine/log/development.log
```

### Example Logs

```
Parent to Child: Creating child issue for parent #123
Parent to Child: Replicating fields from parent issue #123 to child
  Field priority_id: 2
  Field assigned_to_id: 5
  Field category_id: 1
  Field fixed_version_id: 0
  Field description: [Child of Issue #123]\n\nOriginal description...
  Field due_date: 2026-06-01
  Field start_date: 2026-05-25
  Field estimated_hours: 8.0
Parent to Child: Successfully created child issue #124
```

## Troubleshooting Integration

### Plugin not appearing in Admin → Plugins

**Cause**: Plugin not properly installed or init.rb has syntax error

**Solution**:
```bash
# Check directory permissions
ls -la /path/to/redmine/plugins/redmine_parent_to_child_update/

# Check init.rb syntax
ruby -c /path/to/redmine/plugins/redmine_parent_to_child_update/init.rb

# Restart Redmine
touch /path/to/redmine/tmp/restart.txt
```

### Dialog doesn't appear

**Cause**: Issue type not in configured parent types, or plugin disabled

**Solution**:
```bash
# 1. Check plugin is enabled
# Admin → Plugins → check "Enable" checkbox

# 2. Verify issue type configuration
# Admin → Plugins → Check "Parent Issue Types" field

# 3. Check issue type name matches exactly
# Admin → Issue Types → verify exact name
```

### Child issue not created

**Cause**: User permission denied or tracker invalid

**Solution**:
```bash
# 1. Check user permissions
# Admin → Roles & Permissions → Verify "Add Issues"

# 2. Check tracker exists
# Admin → Trackers

# 3. Check Rails log for error details
tail -f log/production.log | grep "Parent to Child"
```

## Rollback Procedure

If you need to disable the plugin:

1. **In Redmine UI**:
   - Admin → Plugins → Parent to Child Update → Delete

2. **In Filesystem**:
   ```bash
   rm -rf /path/to/redmine/plugins/redmine_parent_to_child_update
   ```

3. **Restart Redmine**:
   ```bash
   touch /path/to/redmine/tmp/restart.txt
   ```

No database cleanup needed (no migrations were run).

## Next Steps

1. ✓ Follow Deployment Guide from DEPLOYMENT_GUIDE.md
2. ✓ Configure parent issue types based on your workflow
3. ✓ Test with non-production project
4. ✓ Train users on new workflow
5. ✓ Enable debug logging initially
6. ✓ Monitor logs for first week
7. ✓ Gather user feedback
8. ✓ Adjust configuration as needed

---

**Version**: 1.0.0  
**Last Updated**: 2026-05-24  
**For Support**: See README.rdoc and PROJECT_OVERVIEW.md
