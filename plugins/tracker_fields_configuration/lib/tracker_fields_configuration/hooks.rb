# Tracker Fields Configuration - Hooks
#
# Renders no visible UI of its own. On the issue new/edit form it emits a
# small inline <script> that moves the DOM row of each promoted custom
# field so it sits right after the standard field the admin configured,
# instead of down in the separate "Custom fields" box.
#
# We hook view_layouts_base_body_bottom (fires on every page render, and is
# already relied on elsewhere in this Redmine instance - see
# redmine_notification_bell's hooks.rb) rather than an issue-form-specific
# hook such as view_issues_form_details_bottom, which was tried first but
# never actually fired in this environment.
#
# Because view_layouts_base_body_bottom only fires once, for the initial
# full-page render - not on the Ajax reload Redmine performs when the
# tracker or project dropdown changes on the form - we embed rules for
# every tracker configured under the issue's project up front, and use a
# MutationObserver on the attributes box to reapply them whenever Redmine
# swaps that box out after a tracker/project change.
#
# Implementation notes:
# - We move the actual field row (label + input), we never re-render or
#   duplicate the field, so validation, required-field checks and Ajax
#   value updates all keep working exactly as Redmine expects.
# - The MutationObserver guards against re-entrant loops by only moving a
#   row when it isn't already immediately after its target anchor.
module TrackerFieldsConfiguration
  class Hooks < Redmine::Hook::ViewListener
    ISSUE_FORM_ACTIONS = %w[new create edit update].freeze

    def view_layouts_base_body_bottom(context = {})
      controller = context[:controller]
      return '' unless controller
      return '' unless controller.controller_name == 'issues'
      return '' unless ISSUE_FORM_ACTIONS.include?(controller.action_name)
      return '' unless TrackerFieldsConfiguration.enabled?

      issue = controller.instance_variable_get(:@issue)
      return '' unless issue && issue.project_id

      config = TrackerFieldsConfiguration.rules_by_tracker(issue.project_id)
      return '' if config.empty?

      config_json = config.map { |tracker_id, rules|
        rules_json = rules.map { |r|
          "{\"cf\":#{r[:custom_field_id].to_i},\"after\":#{r[:after_field].to_s.inspect}}"
        }.join(',')
        "#{tracker_id.to_s.inspect}:[#{rules_json}]"
      }.join(',')

      <<~HTML.html_safe
        <script type="text/javascript">
        (function(){
          var TFC_CONFIG = {#{config_json}};

          function rowOf(el) {
            if (!el) return null;
            return el.closest('p') || el.parentElement;
          }

          function currentTrackerId() {
            var el = document.getElementById('issue_tracker_id');
            return el ? el.value : null;
          }

          function tfcApply() {
            var tid = currentTrackerId();
            var rules = tid && TFC_CONFIG[tid];
            if (!rules || !rules.length) return;

            var lastRowByAnchor = {};
            var touchedParents = [];

            rules.forEach(function(rule) {
              var cfEl = document.querySelector('[id^="issue_custom_field_values_' + rule.cf + '"]');
              var cfRow = rowOf(cfEl);
              if (!cfRow) return;

              var refRow = lastRowByAnchor[rule.after] || rowOf(document.getElementById('issue_' + rule.after));
              if (!refRow || refRow === cfRow) return;

              if (refRow.nextElementSibling !== cfRow) {
                var origParent = cfRow.parentNode;
                refRow.parentNode.insertBefore(cfRow, refRow.nextElementSibling);
                if (origParent && origParent !== refRow.parentNode && touchedParents.indexOf(origParent) === -1) {
                  touchedParents.push(origParent);
                }
              }

              cfRow.classList.add('tfc-promoted-field');
              lastRowByAnchor[rule.after] = cfRow;
            });

            // If a "Custom fields" box is now empty because every field in
            // it was promoted away, hide the empty box instead of leaving
            // a blank fieldset behind.
            touchedParents.forEach(function(parent) {
              try {
                if (parent.children.length === 0) {
                  var fieldset = parent.closest('fieldset');
                  (fieldset || parent).style.display = 'none';
                }
              } catch (e) { /* best effort only */ }
            });
          }

          document.addEventListener('DOMContentLoaded', function() {
            tfcApply();

            // Redmine reloads the attributes box via Ajax when the tracker
            // or project changes on the new/edit issue form - watch for
            // that and reapply. The nextElementSibling check in tfcApply
            // above makes repeat calls a no-op once fields are in place.
            var target = document.getElementById('all_attributes') || document.body;
            var observer = new MutationObserver(function() { tfcApply(); });
            observer.observe(target, { childList: true, subtree: true });
          });
        })();
        </script>
      HTML
    end
  end
end
