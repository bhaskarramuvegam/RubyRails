# Tracker Fields Configuration - Hidden Fields Hooks
#
# A separate feature from field promotion (see hooks.rb): lets an admin
# hide selected standard or custom fields entirely, per project + tracker,
# from both the issue form and the read-only issue show page.
#
# This is intentionally implemented as its OWN Redmine::Hook::ViewListener
# subclass, in its own file, reading its own settings key
# (project_tracker_hidden_fields). Redmine calls every listener class that
# implements a given hook and concatenates their output, so this runs
# alongside TrackerFieldsConfiguration::Hooks without either one touching
# the other's code - a bug here cannot break field promotion, and vice
# versa.
#
# Field keys are prefixed the same way tracker_popup_fields does in
# redmine_parent_to_child_update: "cf_<id>" for a custom field, "std_<key>"
# for a standard field (matching TrackerFieldsConfiguration::
# STANDARD_FIELDS' :key values), or "ext_<key>" for an admin-registered
# field from another plugin (e.g. Redmine Agile's Sprint field) that isn't
# a Redmine CustomField and so can't be auto-discovered.
module TrackerFieldsConfiguration
  class HiddenFieldsHooks < Redmine::Hook::ViewListener
    ISSUE_ACTIONS = %w[new create edit update show].freeze

    def view_layouts_base_body_bottom(context = {})
      controller = context[:controller]
      return '' unless controller
      return '' unless controller.controller_name == 'issues'
      return '' unless ISSUE_ACTIONS.include?(controller.action_name)
      return '' unless TrackerFieldsConfiguration.enabled?

      issue = controller.instance_variable_get(:@issue)
      return '' unless issue && issue.project_id && issue.tracker_id

      config = TrackerFieldsConfiguration.hidden_keys_by_tracker(issue.project_id)
      return '' if config.empty?

      label_by_key = TrackerFieldsConfiguration::STANDARD_FIELDS.each_with_object({}) do |f, acc|
        acc[f[:key]] = ::I18n.t(f[:label_key])
      end
      extra_labels_by_tracker = TrackerFieldsConfiguration.extra_field_labels_by_tracker(issue.project_id)

      config_json = config.map { |tracker_id, keys|
        keys_json = keys.map { |k| k.to_s.inspect }.join(',')
        "#{tracker_id.to_s.inspect}:[#{keys_json}]"
      }.join(',')

      labels_json = label_by_key.map { |k, v| "#{k.inspect}:#{v.to_s.inspect}" }.join(',')

      extra_labels_json = extra_labels_by_tracker.map { |tracker_id, labels|
        pairs = labels.map { |k, v| "#{k.to_s.inspect}:#{v.to_s.inspect}" }.join(',')
        "#{tracker_id.to_s.inspect}:{#{pairs}}"
      }.join(',')

      <<~HTML.html_safe
        <script type="text/javascript">
        (function(){
          var TFC_HIDDEN_CONFIG = {#{config_json}};
          var TFC_HIDDEN_STD_LABELS = {#{labels_json}};
          var TFC_HIDDEN_EXTRA_LABELS = {#{extra_labels_json}};
          var TFC_HIDDEN_FALLBACK_TRACKER_ID = #{issue.tracker_id.to_i.to_s.inspect};

          function tfcHideCurrentTrackerId() {
            var el = document.getElementById('issue_tracker_id');
            return el ? el.value : TFC_HIDDEN_FALLBACK_TRACKER_ID;
          }

          function tfcHideCurrentKeys() {
            var tid = tfcHideCurrentTrackerId();
            return (tid && TFC_HIDDEN_CONFIG[tid]) || [];
          }

          // ── Form: hide the <p> row wrapping the input/select ──────────────
          function tfcHideFormRowOf(el) {
            if (!el) return null;
            return el.closest('p') || el.parentElement;
          }

          function tfcHideFindFormRow(key) {
            if (key.indexOf('std_') === 0) {
              return tfcHideFormRowOf(document.getElementById('issue_' + key.slice(4)));
            }
            if (key.indexOf('ext_') === 0) {
              // Extra fields are matched the same way as standard fields -
              // the admin enters the exact id suffix after "issue_".
              return tfcHideFormRowOf(document.getElementById('issue_' + key.slice(4)));
            }
            if (key.indexOf('cf_') === 0) {
              var cfId = key.slice(3);
              var el = document.getElementById('issue_custom_field_values_' + cfId) ||
                       document.querySelector('[id^="issue_custom_field_values_' + cfId + '_"]');
              return tfcHideFormRowOf(el);
            }
            return null;
          }

          // ── Show page: hide the div.attribute row ─────────────────────────
          function tfcHideLabelText(el) {
            return (el.textContent || '').replace(/[:：\s]+$/, '').trim();
          }

          function tfcHideFindShowRowByLabel(text) {
            var labels = document.querySelectorAll('.attributes .label');
            for (var i = 0; i < labels.length; i++) {
              if (tfcHideLabelText(labels[i]) === text) {
                return labels[i].closest('.attribute');
              }
            }
            return null;
          }

          function tfcHideFindShowRow(key) {
            if (key.indexOf('cf_') === 0) {
              return document.querySelector('.attributes .' + key);
            }
            if (key.indexOf('std_') === 0) {
              var label = TFC_HIDDEN_STD_LABELS[key.slice(4)];
              return label ? tfcHideFindShowRowByLabel(label) : null;
            }
            if (key.indexOf('ext_') === 0) {
              // Extra fields' labels vary per tracker (admin-entered), so
              // they're looked up per current tracker rather than from a
              // fixed global map like TFC_HIDDEN_STD_LABELS.
              var tid = tfcHideCurrentTrackerId();
              var trackerLabels = TFC_HIDDEN_EXTRA_LABELS[tid] || {};
              var label = trackerLabels[key.slice(4)];
              return label ? tfcHideFindShowRowByLabel(label) : null;
            }
            return null;
          }

          function tfcApplyHidden() {
            var keys = tfcHideCurrentKeys();
            if (!keys.length) return;

            keys.forEach(function(key) {
              var formRow = tfcHideFindFormRow(key);
              if (formRow) formRow.style.display = 'none';

              var showRow = tfcHideFindShowRow(key);
              if (showRow) showRow.style.display = 'none';
            });
          }

          document.addEventListener('DOMContentLoaded', function() {
            tfcApplyHidden();

            // Reapply after Redmine's Ajax tracker/project reload on the
            // issue form, same as the field-promotion script does.
            var target = document.getElementById('all_attributes') || document.body;
            var observer = new MutationObserver(function() { tfcApplyHidden(); });
            observer.observe(target, { childList: true, subtree: true });
          });
        })();
        </script>
      HTML
    end
  end
end
