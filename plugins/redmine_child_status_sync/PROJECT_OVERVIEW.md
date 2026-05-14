# Redmine Child Status Sync Plugin - Overview

## 📋 Project Description

This is a **Redmine plugin** that automatically synchronizes parent issue status when child issues are updated with any status change.

**Version:** 0.0.1 (Modified)  
**Plugin Name:** redmine_child_status_sync

---

## ✅ What It Does

### Core Functionality
When any **child issue** status is updated to ANY status, the plugin automatically updates the **parent issue** status to match the child's new status.

### Use Case Scenario
```
Parent Task (Status: New)
├── Child Task 1 (Status: New)
├── Child Task 2 (Status: New) → Updates to "In Progress"
└── Child Task 3 (Status: New)

Result: Parent Task automatically updates to "In Progress"
```

### Key Features
- ✅ **Automatic Status Sync**: Parent status updates to match ANY child status change
- ✅ **Flexible Sync**: Works with any status (In Progress, Testing, Ready, etc.)
- ✅ **Child-Only Trigger**: Only works for issues that have a parent
- ✅ **Safe Operation**: Only updates status when actual changes are made
- ✅ **Logging**: Records status changes for debugging

---

## 🔧 How It Works

### Architecture
1. **Patches Issue Model**: Modifies Redmine's `Issue` model at runtime using monkey patching
2. **After-Save Hook**: Uses `after_save` callback to monitor status changes
3. **Conditional Logic**: Triggers when child status changes to ANY status
4. **Parent Update**: Finds parent issue and updates its status to match

### Process Flow
```
Child Issue Status Update
    ↓
Plugin's after_save Callback Triggers
    ↓
Check: Is this a child issue? (has parent_id)
    ↓
Check: Status changed?
    ↓
Find Parent Issue
    ↓
Update Parent Status to Match Child's New Status
    ↓
Log the Change
```

### Technical Details
- **Status Detection**: Dynamically gets the current status of the child issue
- **Parent Lookup**: Uses `parent_id` to find parent issue
- **Update Method**: Uses `update_column` for direct database update (bypasses validations)
- **Error Handling**: Gracefully handles invalid parent IDs and missing statuses

---

## ⚙️ Requirements

- **Redmine:** 4.x or newer
- **Ruby:** 2.6+
- **Database:** PostgreSQL or MySQL
- **Issue Status:** Any custom statuses you want to sync (no specific status required)

---

## 📦 Installation

### Step 1: Copy Plugin
```bash
# Copy to Redmine plugins directory
cp -r redmine_child_status_sync /path/to/redmine/plugins/
```

### Step 2: Restart Redmine
```bash
cd /path/to/redmine
bundle exec rails server
```

---

## 🧪 Testing

### Run Tests
```bash
cd /path/to/redmine
bundle exec rake test:plugins[name=redmine_child_status_sync]
```

### Test Coverage

The plugin has been modified to sync ANY status change, so test cases should include:
- Parent status updates to match child's new status (any status)
- No update if parent is already in the same status
- Proper handling when issue has no parent
- Correct logging of status changes
- Invalid parent ID handling

---

## 📂 Project Structure

```
redmine_child_status_sync/
├── init.rb                          # Plugin initialization & registration
├── README.rdoc                      # Installation & usage documentation
├── PROJECT_OVERVIEW.md              # This detailed overview
├── config/
│   ├── routes.rb                    # Plugin routes (empty)
│   └── locales/
│       └── en.yml                   # Internationalization (empty)
├── lib/
│   └── redmine_child_status_sync/
│       └── issue_patch.rb           # ✅ Main plugin logic (MODIFIED)
└── test/
    └── unit/
        └── test_child_status_sync.rb # ✅ Test suite
```

---

## ⚠️ Configuration Notes

### Flexible Status Sync
- **No Hardcoded Status**: Works with any status defined in Redmine
- **Dynamic**: Uses the child's current status directly
- **No Configuration Needed**: Works out-of-the-box with any statuses

### Advanced Customization
If you need project-specific or tracker-specific logic, you can extend the plugin by modifying `issue_patch.rb`:
```ruby
# Example: Only sync if child is assigned to a specific user
return unless assigned_to_id == some_user_id

# Example: Only sync for certain projects
return unless parent_issue.project_id == specific_project_id

# Example: Skip sync for certain status types
return if some_excluded_status_ids.include?(status_id)
```

---

## 🚀 Usage Examples

### Basic Workflow - Any Status
1. **Create Parent Issue**: "Implement User Authentication" (Status: New)
2. **Create Child Issues**:
   - "Design Database Schema" (Status: New)
   - "Implement Login Logic" (Status: New)
   - "Add Password Reset" (Status: New)
3. **Update Child Status**: Change "Implement Login Logic" to "In Progress"
4. **Automatic Result**: Parent "Implement User Authentication" automatically becomes "In Progress"

### Multiple Status Changes Example
```
Initial State:
Parent: "Setup Infrastructure" (Status: New)
├── Child 1: Database Setup (Status: New)
├── Child 2: Server Setup (Status: New)

Step 1: Update Child 1 to "In Progress"
Result: Parent → "In Progress"

Step 2: Update Child 2 to "Testing"
Result: Parent → "Testing"

Step 3: Update Child 1 to "Completed"
Result: Parent → "Completed"
```

### Status Flow with Any Statuses
```
New → In Progress (manual child update)
    ↓
Parent automatically updates to In Progress
    ↓
In Progress → Testing (manual child update)
    ↓
Parent automatically updates to Testing
    ↓
Testing → Ready for Release (manual child update)
    ↓
Parent automatically updates to Ready for Release
```

---

## 🔍 Troubleshooting

### Common Issues

**Plugin Not Loading**
```bash
# Check Redmine logs
tail -f /path/to/redmine/log/production.log
```

**Status Not Updating**
- Verify the child issue actually has a parent
- Check if the status change is being saved properly
- Review Redmine logs for any errors

**Tests Failing**
- Ensure test database has required issue statuses
- Check that plugin patch is properly loaded in test environment

### Debug Logging
The plugin logs status changes:
```bash
# Check logs for entries like:
# "Child Status Sync: Updated parent issue #123 status to 'Development In Progress' because child #456 was updated"
```

---

## 🔗 Links

- Redmine Plugin Development: https://www.redmine.org/projects/redmine/wiki/Plugin_development
- Rails Callbacks: https://guides.rubyonrails.org/active_record_callbacks.html
- Monkey Patching: https://www.redmine.org/projects/redmine/wiki/Plugin_Internals

---

## 📞 Support

For issues with this plugin:
1. Check the test file for expected behavior
2. Review Redmine logs for error messages
3. Verify issue status configuration
4. Test with a simple parent-child relationship

**Last Updated:** April 22, 2026