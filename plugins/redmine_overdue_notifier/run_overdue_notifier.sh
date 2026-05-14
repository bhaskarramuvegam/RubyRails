#!/bin/bash
cd /var/lib/redmine
RAILS_ENV=production bundle exec rake redmine_overdue_notifier:send_notifications

