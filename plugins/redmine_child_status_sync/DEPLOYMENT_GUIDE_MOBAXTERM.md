# Redmine Child Status Sync Plugin - Deployment Guide (MobaXterm)

## Overview
This guide provides step-by-step instructions to deploy the **redmine_child_status_sync** plugin to a Linux Redmine server (192.168.3.91) using **MobaXterm** on Windows.

**Server Details:**
- **IP Address**: 192.168.3.91
- **Username**: vegam
- **Password**: Vegam@123
- **Redmine Location**: /var/lib/redmine

---

## Prerequisites

### On Your Windows Machine
- ✅ MobaXterm installed (free version available)
- ✅ Access to the plugin files locally
- ✅ Server credentials (IP, username, password)

### On the Linux Server
- ✅ SSH access enabled (port 22)
- ✅ Redmine installed at `/var/lib/redmine`
- ✅ Super user (sudo) access available
- ✅ Web server running (Apache, Nginx, or Puma)

---

## Step 1: Prepare the Plugin Locally

### 1.1 Locate the Plugin Folder
Navigate to your local plugin directory:
```
C:\Users\Aureo\Downloads\vegam_redmine_plugins_siddhant\vegam_redmine_plugins_siddhant\plugins\redmine_child_status_sync
```

### 1.2 Verify Plugin Contents
Ensure the plugin folder contains:
- ✅ `init.rb` - Plugin initialization
- ✅ `README.rdoc` - Documentation
- ✅ `PROJECT_OVERVIEW.md` - Project details
- ✅ `DEPLOYMENT_GUIDE_MOBAXTERM.md` - This guide
- ✅ `lib/redmine_child_status_sync/issue_patch.rb` - Core plugin code (MODIFIED)
- ✅ `config/routes.rb` - Routes configuration
- ✅ `test/` - Test directory

### 1.3 Create ZIP Archive
1. Right-click the `redmine_child_status_sync` folder
2. Select: **Send to → Compressed (zipped) folder**
3. Name it: `redmine_child_status_sync.zip`
4. Save to your Desktop or Documents folder for easy access

---

## Step 2: Open MobaXterm and Create SFTP Session

### 2.1 Launch MobaXterm
- Open MobaXterm application on your Windows machine

### 2.2 Create SFTP Session for File Transfer
1. Click the **"Session"** button (top-left of MobaXterm)
2. Select the **"SFTP"** tab
3. Fill in the connection details:
   - **Remote host**: `192.168.3.91`
   - **Username**: `vegam`
   - **Port**: `22`
   - **Password**: `Vegam@123` (optional - can be prompted later)
4. Click **"OK"**
5. MobaXterm will open an SFTP window with two panes (Local and Remote)

### 2.3 Navigate to Upload Directory
**On the Remote side (right pane):**
- Navigate to `/tmp/` directory
- This is where we'll upload the ZIP file

**On the Local side (left pane):**
- Browse to where you saved `redmine_child_status_sync.zip`

---

## Step 3: Upload Plugin ZIP File via SFTP

### 3.1 Drag and Drop Upload
1. In the **Local pane** (left), locate `redmine_child_status_sync.zip`
2. **Drag and drop** it to the **Remote pane** (right) in `/tmp/` directory
3. Wait for upload to complete (you'll see a progress indicator)

**Alternative: Manual Upload**
If drag-and-drop doesn't work:
1. Right-click on the ZIP file in the Local pane
2. Select **"Upload"** or **"Copy"**
3. Confirm upload when prompted

### 3.2 Verify Upload
In the Remote pane, you should see:
```
/tmp/redmine_child_status_sync.zip
```

---

## Step 4: Create SSH Session to Install Plugin

### 4.1 Open SSH Terminal
1. Click the **"Session"** button again
2. Select the **"SSH"** tab
3. Fill in connection details:
   - **Remote host**: `192.168.3.91`
   - **Username**: `vegam`
   - **Port**: `22`
4. Click **"OK"**
5. MobaXterm opens a terminal window
6. Enter password when prompted: `Vegam@123`

### 4.2 You're Now Connected
You should see a terminal prompt:
```
vegam@192.168.3.91:~$
```

---

## Step 5: Install the Plugin

### 5.1 Switch to Super User
```bash
sudo su
```
When prompted for password, enter: `Vegam@123`

You should now see:
```
root@192.168.3.91:~#
```

### 5.2 Navigate to Redmine Directory
```bash
cd /var/lib/redmine
```

### 5.3 Unzip Plugin into Plugins Directory
```bash
unzip /tmp/redmine_child_status_sync.zip -d plugins/
```

**Expected Output:**
```
Archive:  /tmp/redmine_child_status_sync.zip
   creating: plugins/redmine_child_status_sync/
  inflating: plugins/redmine_child_status_sync/init.rb
  inflating: plugins/redmine_child_status_sync/README.rdoc
  ...
```

### 5.4 Verify Plugin Installation
```bash
ls -la plugins/redmine_child_status_sync/
```

**Expected Output:**
```
total XX
drwxr-xr-x  X  root root  XXXX  Apr 22 12:00 .
drwxr-xr-x  X  root root  XXXX  Apr 22 12:00 ..
-rw-r--r--  1  root root  XXXX  Apr 22 12:00 init.rb
-rw-r--r--  1  root root  XXXX  Apr 22 12:00 README.rdoc
-rw-r--r--  1  root root  XXXX  Apr 22 12:00 PROJECT_OVERVIEW.md
-rw-r--r--  1  root root  XXXX  Apr 22 12:00 DEPLOYMENT_GUIDE_MOBAXTERM.md
drwxr-xr-x  X  root root  XXXX  Apr 22 12:00 config
dr-xr-xr-x  X  root root  XXXX  Apr 22 12:00 lib
drwxr-xr-x  X  root root  XXXX  Apr 22 12:00 test
```

### 5.5 Fix Permissions (Important)
```bash
# Find web server user
ps aux | grep -E "(apache|nginx|www-data)" | head -1
```

Set correct permissions (assuming www-data):
```bash
chown -R www-data:www-data /var/lib/redmine/plugins/redmine_child_status_sync/
chmod -R 755 /var/lib/redmine/plugins/redmine_child_status_sync/
```

Verify permissions:
```bash
ls -ld /var/lib/redmine/plugins/redmine_child_status_sync/
```

---

## Step 6: Restart Web Server

### 6.1 Identify Running Web Server
```bash
systemctl list-units --type=service | grep -E "(apache|nginx|puma)"
```

**Expected Output (example):**
```
apache2.service     loaded active running Apache HTTP Server
```

### 6.2 Restart the Web Server

**For Apache:**
```bash
systemctl restart apache2
```

**For Nginx:**
```bash
systemctl nginx restart
```

**For Puma:**
```bash
systemctl restart puma
```

### 6.3 Verify Restart Successful
```bash
systemctl status apache2
```

Look for:
```
● apache2.service - Apache HTTP Server
     Loaded: loaded (/lib/systemd/units/system/apache2.service; enabled)
     Active: active (running) since Wed 2026-04-22 12:00:00 UTC
```

---

## Step 7: Clear Redmine Cache (Optional but Recommended)

### 7.1 Clear Temporary Files
```bash
cd /var/lib/redmine
rm -rf tmp/cache/*
```

### 7.2 Restart Web Server Again
```bash
systemctl restart apache2
```

---

## Step 8: Validate Plugin Installation

### 8.1 Check Redmine Logs
In the SSH terminal, view the Redmine production log:
```bash
tail -50 /var/lib/redmine/log/production.log
```

**Look for:**
- ✅ No `ERROR` messages related to redmine_child_status_sync
- ✅ Plugin loading confirmation messages
- ✅ No `permission denied` errors

### 8.2 Test via Web Browser
1. Open your web browser
2. Navigate to: `http://192.168.3.91` (or your configured Redmine URL)
3. **Log in** as an administrator

### 8.3 Check Plugin List
1. Click **"Administration"** in the top menu
2. Select **"Plugins"** from the left sidebar
3. Look for: **"Redmine Child Status Sync"** in the plugin list
4. Verify status shows as loaded/active

**Expected Display:**
```
Redmine Child Status Sync
Version: 0.0.1
Description: Automatically synchronizes parent issue status when child issues are updated
```

---

## Step 9: Test Functionality

### 9.1 Create Test Issues
1. In Redmine, navigate to a project
2. **Create a Parent Issue**:
   - Title: "Test Parent Task"
   - Status: "New"

3. **Create a Child Issue**:
   - Title: "Test Child Task"
   - Status: "New"
   - Set this as a subtask of the parent issue

### 9.2 Test Status Synchronization
1. Open the child issue
2. Change its status to any status (e.g., "In Progress", "Testing", etc.)
3. **Save the change**
4. Open the **parent issue**
5. **Verify**: Parent status should automatically update to match the child's new status

### 9.3 Test Multiple Status Changes
1. Change child status to "Testing"
   - **Verify**: Parent updates to "Testing"
2. Change child status to "Ready for Release"
   - **Verify**: Parent updates to "Ready for Release"

### 9.4 Verify No Sync for Standalone Issues
1. Create an issue **without a parent**
2. Change its status
3. **Verify**: No unexpected behavior

---

## Troubleshooting

### Problem: Plugin Not Appearing in Plugin List

**Solution 1: Check File Permissions**
```bash
ls -ld /var/lib/redmine/plugins/redmine_child_status_sync/
```
Should show permissions like: `drwxr-xr-x`

If not, fix with:
```bash
chown -R www-data:www-data /var/lib/redmine/plugins/redmine_child_status_sync/
chmod -R 755 /var/lib/redmine/plugins/redmine_child_status_sync/
```

**Solution 2: Check Redmine Logs**
```bash
tail -100 /var/lib/redmine/log/production.log | grep -i "error\|child_status"
```

**Solution 3: Clear Cache and Restart**
```bash
cd /var/lib/redmine
rm -rf tmp/cache/*
systemctl restart apache2
```

### Problem: Status Not Syncing

**Check:**
1. Is the child issue actually under a parent? (Verify in Redmine UI)
2. Is the status change actually being saved?
3. Check logs for errors:
   ```bash
   tail -50 /var/lib/redmine/log/production.log
   ```

### Problem: "Permission Denied" Errors

**Solution:**
```bash
# Change ownership to web server user
sudo chown -R www-data:www-data /var/lib/redmine/plugins/redmine_child_status_sync/
sudo chmod -R 755 /var/lib/redmine/plugins/redmine_child_status_sync/

# Restart web server
systemctl restart apache2
```

### Problem: Web Server Won't Start

**Check the error:**
```bash
systemctl status apache2
journalctl -xe
```

**Common causes:**
- Port already in use
- Configuration syntax error
- Plugin code error (check logs)

---

## Rollback (If Something Goes Wrong)

### 9.1 Remove Plugin
```bash
sudo su
cd /var/lib/redmine/plugins
rm -rf redmine_child_status_sync/
```

### 9.2 Restart Web Server
```bash
systemctl restart apache2
```

### 9.3 Verify Removal
```bash
# Check plugin is gone
ls -la plugins/ | grep child_status
# Should show nothing
```

---

## Post-Deployment Checklist

- [ ] Plugin ZIP file uploaded to server (`/tmp/`)
- [ ] Plugin unzipped to `/var/lib/redmine/plugins/`
- [ ] Plugin files verified with `ls -la`
- [ ] File permissions set correctly
- [ ] Web server restarted
- [ ] Redmine cache cleared
- [ ] No errors in Redmine logs
- [ ] Plugin appears in Administration → Plugins
- [ ] Test parent/child created successfully
- [ ] Child status change syncs to parent
- [ ] Multiple status changes work correctly
- [ ] No errors in browser console

---

## Quick Command Reference

| Action | Command |
|--------|---------|
| Switch to root | `sudo su` |
| Navigate to Redmine | `cd /var/lib/redmine` |
| Unzip plugin | `unzip /tmp/redmine_child_status_sync.zip -d plugins/` |
| Check permissions | `ls -ld plugins/redmine_child_status_sync/` |
| Fix permissions | `chown -R www-data:www-data plugins/redmine_child_status_sync/` |
| View logs | `tail -50 log/production.log` |
| Clear cache | `rm -rf tmp/cache/*` |
| Restart Apache | `systemctl restart apache2` |
| Check Apache status | `systemctl status apache2` |

---

## Support & Next Steps

### If Plugin Works
- ✅ Deployment is complete!
- ✅ Plugin will continue to work after server restarts
- ✅ Monitor logs regularly for any errors

### If Issues Occur
1. Check all troubleshooting steps above
2. Review Redmine logs: `/var/lib/redmine/log/production.log`
3. Verify file permissions and ownership
4. Ensure web server is running properly

### For Future Updates
Simply repeat this deployment process with the updated plugin ZIP file. The old plugin will be replaced.

---

## Additional Resources

- **Redmine Plugin Documentation**: http://www.redmine.org/projects/redmine/wiki/Plugins
- **MobaXterm Documentation**: https://mobaxterm.mobatek.net/documentation.html
- **Redmine Installation Guide**: http://www.redmine.org/projects/redmine/wiki/RedmineInstall

---

**Document Version**: 1.0  
**Last Updated**: April 22, 2026  
**Plugin Version**: 0.0.1 (Modified - Any Status Sync)  
**Server**: 192.168.3.91  
**Redmine Path**: /var/lib/redmine
