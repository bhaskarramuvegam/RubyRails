# Redmine Parent to Child Update Plugin - Deployment Guide

## Quick Start

This guide will help you deploy the Redmine Parent to Child Update Plugin to your Redmine instance.

## Prerequisites

- Redmine 3.0+ (tested with 4.x and 5.x)
- Ruby 2.0+
- Rails 4.2+
- Git access to your Redmine installation

## Installation Steps

### 1. Download the Plugin

Navigate to your Redmine plugins directory:

```bash
cd /path/to/redmine/plugins
```

Clone or copy the plugin:

```bash
git clone <repository-url> redmine_parent_to_child_update
```

Or if copying manually:

```bash
cp -r redmine_parent_to_child_update /path/to/redmine/plugins/
```

### 2. Verify Plugin Structure

Ensure the plugin has this structure:

```
redmine_parent_to_child_update/
├── init.rb
├── README.rdoc
├── PROJECT_OVERVIEW.md
├── config/
│   ├── locales/
│   │   └── en.yml
│   └── routes.rb
├── lib/
│   └── redmine_parent_to_child_update/
│       ├── issue_patch.rb
│       └── hooks.rb
└── app/
    ├── controllers/
    │   └── redmine_parent_to_child_update/
    │       └── child_issues_controller.rb
    └── views/
        └── settings/
            └── _redmine_parent_to_child_update_settings.html.erb
```

### 3. Install Dependencies (if needed)

```bash
cd /path/to/redmine
bundle install
```

### 4. Run Migrations (if any)

```bash
rake redmine:plugins:migrate PLUGIN=redmine_parent_to_child_update
```

### 5. Restart Redmine

```bash
# For production (Passenger/Puma)
touch tmp/restart.txt

# For development (Webrick)
# Stop and restart with: rails s -b 0.0.0.0 -p 3000
```

Or restart your Redmine service:

```bash
sudo systemctl restart redmine
# or
sudo service redmine restart
```

## Configuration

### 1. Enable Plugin in Redmine

1. Log in to Redmine as an Administrator
2. Click **Administration** → **Plugins**
3. Find **"Parent to Child Update Plugin"**
4. Click the plugin name or **Configure** to open settings

### 2. Configure Plugin Settings

In the plugin settings page, you'll find:

#### Enable Plugin
- **Default**: ✓ (checked)
- **Purpose**: Turn plugin on/off without uninstalling

#### Enable Debug Logging
- **Default**: ✓ (checked)
- **Purpose**: Log all plugin operations to Rails log
- **Useful for**: Troubleshooting issues

#### Automatically Replicate Parent Fields to Child
- **Default**: ✓ (checked)
- **Purpose**: Enable/disable automatic field replication
- **Recommended**: Leave checked

#### Parent Issue Types
- **Default**: `Bug,Feature,Task,Support`
- **Purpose**: Comma-separated list of issue types that trigger the dialog
- **Example**: `CR,Bug,Story,Epic` (Use actual issue type names in your system)

### 3. Customize Parent Issue Types

To configure which issue types trigger the child creation dialog:

1. Go to Administration → Plugins → Parent to Child Update Plugin
2. Find the field "Parent Issue Types (comma-separated)"
3. Enter the issue type names, separated by commas
4. **Important**: Use the exact names of your issue types as they appear in Redmine

Example configurations:

- For standard types: `Bug,Feature,Task,Support`
- For enterprise: `CR,Change Request,Initiative,Epic`
- For all types: Leave empty to apply to all types (not recommended)

### 4. Test Configuration

1. Create a new issue with one of the configured types
2. When submitting the form, you should see the popup dialog
3. Click "Yes, Create Child" to test field replication
4. Verify the child issue is created with parent fields replicated

## Verification

### Verify Plugin is Loaded

1. Go to Administration → Plugins
2. You should see "Parent to Child Update Plugin" v1.0.0 in the list
3. Status should be "✓ Active"

### Check Debug Logs

When debug logging is enabled, check your Rails log:

```bash
# Production
tail -f /path/to/redmine/log/production.log

# Development
tail -f /path/to/redmine/log/development.log
```

Look for lines like:

```
Parent to Child: Creating child issue for parent #123
Parent to Child: Replicating fields from parent issue #123 to child
Parent to Child: Successfully created child issue #124
```

### Test Workflow

1. Create a new issue (configure type)
2. Fill in issue details (title, description, etc.)
3. Click "Save"
4. Verify popup dialog appears
5. Test "Yes" button: Child issue should be created with replicated fields
6. Test "No" button: Only parent issue should be created

## Troubleshooting

### Plugin doesn't appear in Administration > Plugins

**Solution**:
1. Verify plugin directory structure is correct
2. Check permissions: `ls -la /path/to/redmine/plugins/redmine_parent_to_child_update/`
3. Ensure `init.rb` exists and is readable
4. Restart Redmine

### Popup dialog doesn't appear

**Possible causes**:

1. **Plugin not enabled**: Go to Admin → Plugins → Enable plugin
2. **Issue type not configured**: Check Parent Issue Types setting matches your issue type
3. **Issue has parent**: Dialog only shows for new parent issues (without parent)
4. **JavaScript error**: Check browser console (F12) for errors

**Solutions**:
```bash
# Enable debug logging
# Check Rails log for errors
tail -f log/production.log | grep "Parent to Child"

# Verify issue type name matches exactly
# Check Redmine: Administration → Issue Types
```

### Child issue not created

**Possible causes**:

1. **User doesn't have permission**: User needs "Add Issues" permission
2. **Project inactive**: Verify project is active
3. **Tracker invalid**: Selected tracker ID doesn't exist
4. **Database error**: Check Rails log

**Solutions**:
```bash
# Check permissions
# Administration → Roles & Permissions → Check "Add Issues"

# Check tracker exists
# Administration → Trackers

# Check Rails log for detailed error
grep "Parent to Child.*Error" log/production.log
```

### Fields not replicated

**Possible causes**:

1. **Auto-replicate disabled**: Check plugin settings
2. **Field permissions**: Parent/child field permissions differ
3. **Custom field issues**: Custom field values not copying

**Solutions**:
```bash
# Enable debug logging to see field replication details
# Check Rails log output
# Verify custom fields exist in both parent and child

# Example log entry:
# Field priority_id: 2
# Field assigned_to_id: 5
# Custom field field_name: value
```

### Permissions issues

**Solution**:

Ensure users have these permissions:
1. **View Issues** - Can see parent issue
2. **Add Issues** - Can create child issue

Check at: Administration → Roles & Permissions

## Uninstallation

If you need to remove the plugin:

```bash
# 1. Disable in Redmine UI (optional)
# Administration → Plugins → Parent to Child Update → Delete

# 2. Remove plugin directory
rm -rf /path/to/redmine/plugins/redmine_parent_to_child_update

# 3. Restart Redmine
touch /path/to/redmine/tmp/restart.txt
```

## Backup

Before deploying to production, create a backup:

```bash
# Backup plugin directory
cp -r redmine_parent_to_child_update redmine_parent_to_child_update.backup

# Backup database
mysqldump -u root -p redmine_production > redmine_backup_$(date +%Y%m%d).sql
```

## Performance Considerations

- The plugin has minimal performance impact
- Modal dialogs are lightweight (CSS + JavaScript only)
- No database queries on dialog display
- Child creation happens after parent save

## Support & Documentation

- See **README.rdoc** for detailed documentation
- See **PROJECT_OVERVIEW.md** for architecture details
- Check Rails log with debug logging enabled for troubleshooting
- Review error messages in popup dialogs

## Next Steps

1. ✓ Verify plugin installed and enabled
2. ✓ Configure parent issue types
3. ✓ Test with a non-production issue
4. ✓ Enable debug logging if issues occur
5. ✓ Train users on new workflow
6. ✓ Monitor logs for first few days
7. ✓ Gather user feedback

---

**Version**: 1.0.0  
**Last Updated**: 2026-05-24  
**Compatibility**: Redmine 3.0+, Ruby 2.0+
