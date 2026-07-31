# Tracker Fields Configuration - Hooks
#
# Renders no visible UI of its own. On the issue new/edit form AND on the
# read-only issue show page, it emits a small inline <script> that moves
# the DOM row of each promoted custom field so it sits right after the
# standard field the admin configured, instead of down in the separate
# "Custom fields" box.
#
# The show page and the edit/new form use completely different markup for
# fields (confirmed by inspecting both in this Redmine instance), so two
# separate movers are emitted:
#
# - Form (new/create/edit/update): fields are <input>/<select> elements
#   with ids like "issue_custom_field_values_30" (custom) and
#   "issue_priority_id" (standard), each wrapped in a <p>. We move the <p>.
#
# - Show: fields are <div class="..._cf cf_30 attribute"> (custom) and
#   <div class="priority attribute"> (standard), each containing a
#   .label/.value pair. We move the whole .attribute div. Since standard
#   field class names aren't confirmed for every field, the anchor is
#   found by matching the .label text against the field's translated name
#   (e.g. "Priority:") instead of guessing a class name.
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
module TrackerFieldsConfiguration
  class Hooks < Redmine::Hook::ViewListener
    ISSUE_ACTIONS = %w[new create edit update show].freeze

    def view_layouts_base_body_bottom(context = {})
      controller = context[:controller]
      return '' unless controller
      return '' unless controller.controller_name == 'issues'
      return '' unless ISSUE_ACTIONS.include?(controller.action_name)
      return '' unless TrackerFieldsConfiguration.enabled?

      issue = controller.instance_variable_get(:@issue)
      return '' unless issue && issue.project_id && issue.tracker_id

      config = TrackerFieldsConfiguration.rules_by_tracker(issue.project_id)
      return '' if config.empty?

      label_by_key = TrackerFieldsConfiguration::STANDARD_FIELDS.each_with_object({}) do |f, acc|
        acc[f[:key]] = ::I18n.t(f[:label_key])
      end

      config_json = config.map { |tracker_id, rules|
        rules_json = rules.map { |r|
          "{\"cf\":#{r[:custom_field_id].to_i}," \
          "\"after\":#{r[:after_field].to_s.inspect}," \
          "\"label\":#{label_by_key[r[:after_field]].to_s.inspect}}"
        }.join(',')
        "#{tracker_id.to_s.inspect}:[#{rules_json}]"
      }.join(',')

      <<~HTML.html_safe
        <script type="text/javascript">
        (function(){
          var TFC_CONFIG = {#{config_json}};
          var TFC_FALLBACK_TRACKER_ID = #{issue.tracker_id.to_i.to_s.inspect};

          function currentTrackerId() {
            var el = document.getElementById('issue_tracker_id');
            return el ? el.value : TFC_FALLBACK_TRACKER_ID;
          }

          function currentRules() {
            var tid = currentTrackerId();
            return (tid && TFC_CONFIG[tid]) || [];
          }

          // ── Form mover (new/edit): fields are <p>-wrapped inputs ──────────
          function formRowOf(el) {
            if (!el) return null;
            return el.closest('p') || el.parentElement;
          }

          function formFindCustomFieldEl(cfId) {
            return document.getElementById('issue_custom_field_values_' + cfId) ||
                   document.querySelector('[id^="issue_custom_field_values_' + cfId + '_"]');
          }

          function tfcApplyForm() {
            var rules = currentRules();
            if (!rules.length) return;

            var lastRowByAnchor = {};
            var touchedParents = [];

            rules.forEach(function(rule) {
              var cfRow = formRowOf(formFindCustomFieldEl(rule.cf));
              if (!cfRow) return;

              var refRow = lastRowByAnchor[rule.after] || formRowOf(document.getElementById('issue_' + rule.after));
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

          // ── Show-page mover: fields are div.attribute rows ────────────────
          function showLabelText(el) {
            return (el.textContent || '').replace(/[:：\s]+$/, '').trim();
          }

          function showFindRowByLabel(text) {
            var labels = document.querySelectorAll('.attributes .label');
            for (var i = 0; i < labels.length; i++) {
              if (showLabelText(labels[i]) === text) {
                return labels[i].closest('.attribute');
              }
            }
            return null;
          }

          function tfcApplyShow() {
            var rules = currentRules();
            if (!rules.length) return;

            var lastRowByAnchor = {};

            rules.forEach(function(rule) {
              var cfRow = document.querySelector('.attributes .cf_' + rule.cf);
              if (!cfRow) return;

              var refRow = lastRowByAnchor[rule.after] || showFindRowByLabel(rule.label);
              if (!refRow || refRow === cfRow) return;

              if (refRow.nextElementSibling !== cfRow) {
                refRow.parentNode.insertBefore(cfRow, refRow.nextElementSibling);
              }

              cfRow.classList.add('tfc-promoted-field');
              lastRowByAnchor[rule.after] = cfRow;
            });
          }

          function tfcApply() {
            tfcApplyForm();
            tfcApplyShow();
          }

          document.addEventListener('DOMContentLoaded', function() {
            tfcApply();

            // Redmine reloads the attributes box via Ajax when the tracker
            // or project changes on the new/edit issue form - watch for
            // that and reapply. The nextElementSibling checks above make
            // repeat calls a no-op once fields are already in place.
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
