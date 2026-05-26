# Redmine Parent to Child Update - Hooks
# This module provides hooks to inject the child creation dialog into the issue creation flow

module RedmineParentToChildUpdate
  class Hooks < Redmine::Hook::ViewListener
    # Inject JavaScript and HTML for the child creation popup into the issue form
    def view_issues_form_details_bottom(context = {})
      issue = context[:issue]
      form = context[:f]

      return unless issue.parent_child_update_enabled?
      return if issue.parent_id.present? # Don't show for child issues

      output = +""
      
      # Add inline styles for modal
      output << "<style type='text/css'>"
      output << ".child-creation-modal { display: none; position: fixed; z-index: 1000; left: 0; top: 0; width: 100%; height: 100%; background-color: rgba(0,0,0,0.5); font-family: Arial, sans-serif; }"
      output << ".child-creation-content { background-color: white; margin: 10% auto; padding: 20px; border: 1px solid #888; width: 500px; border-radius: 5px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }"
      output << ".child-creation-content h3 { margin-top: 0; color: #333; }"
      output << ".child-creation-content p { color: #666; line-height: 1.6; }"
      output << ".child-creation-buttons { text-align: center; margin-top: 20px; }"
      output << ".child-creation-buttons button { padding: 10px 20px; margin: 0 5px; font-size: 14px; border-radius: 3px; border: 1px solid #ccc; background-color: #f5f5f5; cursor: pointer; }"
      output << ".child-creation-buttons button:hover { background-color: #e0e0e0; }"
      output << ".child-creation-buttons button.yes-btn { background-color: #4CAF50; color: white; border-color: #45a049; }"
      output << ".child-creation-buttons button.yes-btn:hover { background-color: #45a049; }"
      output << ".child-creation-buttons button.no-btn { background-color: #f44336; color: white; border-color: #da190b; }"
      output << ".child-creation-buttons button.no-btn:hover { background-color: #da190b; }"
      output << "</style>"

      # Add the modal HTML
      output << "<div id='childCreationModal' class='child-creation-modal'>"
      output << "  <div class='child-creation-content'>"
      output << "    <h3>Create Child Issue</h3>"
      output << "    <p>Would you like to create a child issue (e.g., User Story) for this #{issue.tracker.name}?</p>"
      output << "    <p>If yes, the child issue will inherit all relevant fields from the parent issue.</p>"
      output << "    <div class='child-creation-buttons'>"
      output << "      <button type='button' class='yes-btn' onclick='handleChildCreation(true)'>Yes, Create Child</button>"
      output << "      <button type='button' class='no-btn' onclick='handleChildCreation(false)'>No, Create #{issue.tracker.name} Only</button>"
      output << "    </div>"
      output << "  </div>"
      output << "</div>"

      # Add JavaScript to handle the dialog
      output << "<script type='text/javascript'>"
      output << "var shouldCreateChild = null;"
      output << "var showChildDialog = #{issue.should_show_child_popup?.to_s.downcase};"
      output << ""
      output << "function handleChildCreation(createChild) {"
      output << "  shouldCreateChild = createChild;"
      output << "  document.getElementById('childCreationModal').style.display = 'none';"
      output << "  if (createChild) {"
      output << "    showChildCreationForm();"
      output << "  }"
      output << "}"
      output << ""
      output << "function showChildCreationForm() {"
      output << "  var childModal = document.createElement('div');"
      output << "  childModal.id = 'childDetailsModal';"
      output << "  childModal.className = 'child-creation-modal';"
      output << "  childModal.style.display = 'block';"
      output << "  childModal.innerHTML = getChildFormHTML();"
      output << "  document.body.appendChild(childModal);"
      output << "}"
      output << ""
      output << "function getChildFormHTML() {"
      output << "  var availableTrackers = #{issue.available_child_trackers.map { |t| { id: t.id, name: t.name } }.to_json};"
      output << "  var additionalTrackers = #{issue.additional_child_trackers.map { |t| { id: t.id, name: t.name } }.to_json};"
      output << "  var html = '<div class=\"child-creation-content\">';"
      output << "  html += '<h3>Create Child Issue</h3>';"
      output << "  html += '<p>Select the type of child issue to create:</p>';"
      output << "  html += '<select id=\"childTracker\" style=\"width: 100%; padding: 8px; font-size: 14px; margin: 10px 0;\">';"
      output << "  html += '<option value=\"\">-- Select Issue Type --</option>';"
      output << "  availableTrackers.forEach(function(tracker) {"
      output << "    html += '<option value=\"' + tracker.id + '\">' + tracker.name + '</option>';"
      output << "  });"
      output << "  html += '</select>';"
      output << "  html += '<div style=\"margin: 15px 0;\">';"
      output << "  html += '<label>Child Issue Subject:</label>';"
      output << "  html += '<input type=\"text\" id=\"childSubject\" placeholder=\"Enter subject for child issue\" style=\"width: 100%; padding: 8px; font-size: 14px; margin-top: 5px;\">';"
      output << "  html += '</div>';"
      output << "  if (additionalTrackers.length) {"
      output << "    html += '<div style=\"margin: 15px 0;\">';"
      output << "    html += '<label>Create additional child issues:</label>';"
      output << "    additionalTrackers.forEach(function(tracker) {"
      output << "      html += '<div style=\"margin-top: 5px;\"><label><input type=\"checkbox\" class=\"additional-child-tracker\" value=\"' + tracker.id + '\"> ' + tracker.name + '</label></div>';"
      output << "    });"
      output << "    html += '</div>';"
      output << "  }"
      output << "  html += '<div class=\"child-creation-buttons\">';"
      output << "  html += '<button type=\"button\" class=\"yes-btn\" onclick=\"createChildIssue()\">Create</button>';"
      output << "  html += '<button type=\"button\" class=\"no-btn\" onclick=\"cancelChildCreation()\">Cancel</button>';"
      output << "  html += '</div>';"
      output << "  html += '</div>';"
      output << "  return html;"
      output << "}"
      output << ""
      output << "function createChildIssue() {"
      output << "  var tracker = document.getElementById('childTracker').value;"
      output << "  var subject = document.getElementById('childSubject').value;"
      output << "  if (!tracker || !subject) {"
      output << "    alert('Please select an issue type and enter a subject');"
      output << "    return;"
      output << "  }"
      output << "  document.getElementById('childDetailsModal').style.display = 'none';"
      output << "  var form = document.querySelector('form.edit_issue, form#issue-form, form.new_issue, form[action*=\'/issues\']');"
      output << "  if (!form) {"
      output << "    alert('Unable to locate the issue form. Child creation cannot continue.');"
      output << "    return;"
      output << "  }"
      output << "  var input = document.createElement('input');"
      output << "    input.type = 'hidden';"
      output << "    input.name = 'create_child';"
      output << "    input.value = 'true';"
      output << "    form.appendChild(input);"
      output << ""
      output << "    var trackerInput = document.createElement('input');"
      output << "    trackerInput.type = 'hidden';"
      output << "    trackerInput.name = 'child_tracker_id';"
      output << "    trackerInput.value = tracker;"
      output << "    form.appendChild(trackerInput);"
      output << ""
      output << "    var subjectInput = document.createElement('input');"
      output << "    subjectInput.type = 'hidden';"
      output << "    subjectInput.name = 'child_subject';"
      output << "    subjectInput.value = subject;"
      output << "    form.appendChild(subjectInput);"
      output << ""
      output << "    var additionalCheckboxes = document.querySelectorAll('.additional-child-tracker:checked');"
      output << "    additionalCheckboxes.forEach(function(checkbox) {"
      output << "      var additionalInput = document.createElement('input');"
      output << "      additionalInput.type = 'hidden';"
      output << "      additionalInput.name = 'additional_child_tracker_ids[]';"
      output << "      additionalInput.value = checkbox.value;"
      output << "      form.appendChild(additionalInput);"
      output << "    });"
      output << "  }"
      output << "  form.submit();"
      output << "}"
      output << ""
      output << "function cancelChildCreation() {"
      output << "  document.getElementById('childDetailsModal').remove();"
      output << "  shouldCreateChild = false;"
      output << "}"
      output << ""
      output << "document.addEventListener('DOMContentLoaded', function() {"
      output << "  if (showChildDialog) {"
      output << "    document.getElementById('childCreationModal').style.display = 'block';"
      output << "  }"
      output << "});"
      output << ""
      output << "// Prevent form submission until dialog is handled"
      output << "document.addEventListener('DOMContentLoaded', function() {"
      output << "  var form = document.querySelector('form.edit_issue');"
      output << "  if (form && showChildDialog) {"
      output << "    form.addEventListener('submit', function(e) {"
      output << "      if (shouldCreateChild === null) {"
      output << "        e.preventDefault();"
      output << "        document.getElementById('childCreationModal').style.display = 'block';"
      output << "        return false;"
      output << "      }"
      output << "    });"
      output << "  }"
      output << "});"
      output << "</script>"

      output.html_safe
    end

    # Hook after issue is created to handle child creation or schedule a post-save prompt
    def controller_issues_new_after_save(context = {})
      issue = context[:issue]
      params = context[:params]
      controller = context[:controller]

      return unless issue.persisted?
      return unless issue.parent_child_update_enabled?

      debug_logging = Setting.plugin_redmine_parent_to_child_update['enable_logging'] == '1'
      Rails.logger.info("Parent to Child: Processing after-save hook for parent ##{issue.id}") if debug_logging

      if params[:create_child] == 'true'
        # Immediate creation path (when form provided hidden inputs before submit)
        begin
          child_tracker_id = params[:child_tracker_id].to_i
          child_subject = params[:child_subject]

          tracker = Tracker.find(child_tracker_id)

          # Create child issue as a subtask
          child_issue = Issue.new(
            project: issue.project,
            tracker: tracker,
            subject: child_subject,
            status: (IssueStatus.respond_to?(:default) ? IssueStatus.default : (begin; IssueStatus.find_by(is_default: true); rescue ActiveRecord::StatementInvalid; nil; end) || IssueStatus.first),
            priority: issue.priority,
            author_id: issue.author_id,
            parent_id: issue.id
          )

          # Replicate parent fields and ensure the child is a subtask
          child_issue.replicate_fields_from_parent(issue)

          if child_issue.save
            Rails.logger.info("Parent to Child: Successfully created child issue ##{child_issue.id}") if debug_logging
          else
            Rails.logger.error("Parent to Child: Error creating child issue: #{child_issue.errors.full_messages.join(', ')}") if debug_logging
          end

          additional_ids = Array(params[:additional_child_tracker_ids]).map(&:to_i).select { |value| value > 0 }
          additional_ids.each do |additional_id|
            next if additional_id == tracker.id
            next unless issue.project.trackers.exists?(id: additional_id)

            additional_tracker = Tracker.find(additional_id)
            additional_child = Issue.new(
              project: issue.project,
              tracker: additional_tracker,
              subject: "#{child_subject} - #{additional_tracker.name}",
              status: (IssueStatus.respond_to?(:default) ? IssueStatus.default : (begin; IssueStatus.find_by(is_default: true); rescue ActiveRecord::StatementInvalid; nil; end) || IssueStatus.first),
              priority: issue.priority,
              author_id: issue.author_id,
              parent_id: child_issue.id
            )
            additional_child.replicate_fields_from_parent(issue)
            if additional_child.save
              Rails.logger.info("Parent to Child: Successfully created additional child issue ##{additional_child.id}") if debug_logging
            else
              Rails.logger.error("Parent to Child: Error creating additional child issue: #{additional_child.errors.full_messages.join(', ')}") if debug_logging
            end
          end
        rescue => e
          Rails.logger.error("Parent to Child: Error in child creation: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
        end
      else
        # No immediate child parameters provided — schedule a post-save prompt on the issue show page
        begin
          if controller && controller.session
            controller.session[:redmine_parent_to_child_show_prompt_for] = issue.id
            Rails.logger.info("Parent to Child: Scheduled post-save prompt for issue ##{issue.id}") if debug_logging
          end
        rescue => e
          Rails.logger.warn("Parent to Child: Failed to set session prompt: #{e.message}") if debug_logging
        end
      end
    end

    # Show the child-creation prompt on the issue show page when scheduled
    def view_issues_show_details_bottom(context = {})
      issue = context[:issue]
      controller = context[:controller]

      return unless controller && controller.session
      scheduled_id = controller.session.delete(:redmine_parent_to_child_show_prompt_for)
      return unless scheduled_id == issue.id
      return unless issue.parent_child_update_enabled?

      output = +""
      output << "<style type='text/css'>"
      output << ".child-creation-modal { display: none; position: fixed; z-index: 1000; left: 0; top: 0; width: 100%; height: 100%; background-color: rgba(0,0,0,0.5); font-family: Arial, sans-serif; }"
      output << ".child-creation-content { background-color: white; margin: 10% auto; padding: 20px; border: 1px solid #888; width: 500px; border-radius: 5px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }"
      output << ".child-creation-content h3 { margin-top: 0; color: #333; }"
      output << ".child-creation-content p { color: #666; line-height: 1.6; }"
      output << ".child-creation-buttons { text-align: center; margin-top: 20px; }"
      output << ".child-creation-buttons button { padding: 10px 20px; margin: 0 5px; font-size: 14px; border-radius: 3px; border: 1px solid #ccc; background-color: #f5f5f5; cursor: pointer; }"
      output << ".child-creation-buttons button:hover { background-color: #e0e0e0; }"
      output << ".child-creation-buttons button.yes-btn { background-color: #4CAF50; color: white; border-color: #45a049; }"
      output << ".child-creation-buttons button.yes-btn:hover { background-color: #45a049; }"
      output << ".child-creation-buttons button.no-btn { background-color: #f44336; color: white; border-color: #da190b; }"
      output << ".child-creation-buttons button.no-btn:hover { background-color: #da190b; }"
      output << "</style>"

      output << "<div id='childCreationModalShow' class='child-creation-modal'>"
      output << "  <div class='child-creation-content'>"
      output << "    <h3>Create Child Issue</h3>"
      output << "    <p>Would you like to create a child issue (subtask) for this #{issue.tracker.name}?</p>"
      output << "    <p>If yes, the child issue will inherit all relevant fields from the parent issue.</p>"
      output << "    <div style='margin:12px 0;'>"
      output << "      <label>Select child type:</label>"
      output << "      <select id='childTrackerShow' style='width:100%; margin-top:6px; padding:6px;'>"
      issue.available_child_trackers.each do |t|
        output << "        <option value='#{t.id}'>#{t.name}</option>"
      end
      output << "      </select>"
      output << "    </div>"
      output << "    <div style='margin:12px 0;'>"
      output << "      <label>Child subject:</label>"
      output << "      <input type='text' id='childSubjectShow' style='width:100%; padding:8px; margin-top:6px;' placeholder='Child subject'>"
      output << "    </div>"
      if issue.additional_child_trackers.any?
        output << "    <div style='margin:12px 0;'>"
        output << "      <label>Create additional child issues:</label>"
        issue.additional_child_trackers.each do |t|
          output << "      <div style='margin-top:5px;'><label><input type='checkbox' class='additional-child-tracker-show' value='#{t.id}'> #{t.name}</label></div>"
        end
        output << "    </div>"
      end
      output << "    <div class='child-creation-buttons'>"
      output << "      <button type='button' class='yes-btn' onclick='createChildFromShow(#{issue.id})'>Yes, Create Child</button>"
      output << "      <button type='button' class='no-btn' onclick='document.getElementById(\'childCreationModalShow\').style.display=\'none\''>No</button>"
      output << "    </div>"
      output << "  </div>"
      output << "</div>"

      output << "<script type='text/javascript'>"
      output << "function createChildFromShow(parentId) {"
      output << "  var tracker = document.getElementById('childTrackerShow').value;"
      output << "  var subject = document.getElementById('childSubjectShow').value;"
      output << "  if (!tracker || !subject) { alert('Please select a child type and enter a subject'); return; }"
      output << "  var token = document.querySelector('meta[name=csrf-token]') && document.querySelector('meta[name=csrf-token]').getAttribute('content');"
      output << "  if (!token) {"
      output << "    var tokenInput = document.querySelector('input[name=authenticity_token]');"
      output << "    token = tokenInput && tokenInput.value;"
      output << "  }"
      output << "  if (!token) { alert('CSRF token not found; please reload the page and try again.'); return; }"
      output << "  var data = new FormData();"
      output << "  data.append('tracker_id', tracker);"
      output << "  data.append('subject', subject);"
      output << "  var additional = document.querySelectorAll('.additional-child-tracker-show:checked');"
      output << "  additional.forEach(function(checkbox) { data.append('additional_child_tracker_ids[]', checkbox.value); });"
      output << "  fetch('/redmine_parent_to_child_update/child_issues/create/' + parentId, { method: 'POST', headers: { 'X-CSRF-Token': token, 'X-Requested-With': 'XMLHttpRequest', 'Accept': 'application/json' }, body: data, credentials: 'same-origin' })"
      output << "    .then(function(response) {"
      output << "      return response.text().then(function(text) {"
      output << "        if (!response.ok) {"
      output << "          try { var json = JSON.parse(text); throw new Error(json.error || text); } catch (e) { throw new Error(text); }"
      output << "        }"
      output << "        return JSON.parse(text);"
      output << "      });"
      output << "    })"
      output << "    .then(function(json) {"
      output << "      if (json.error) { alert('Error creating child: ' + json.error); } else if (json.children && json.children.length > 1) { window.location.reload(); } else if (json.children && json.children.length === 1) { window.location = json.children[0].url; } else if (json.url) { window.location = json.url; }"
      output << "    })"
      output << "    .catch(function(err) { alert('Error creating child: ' + err.message); });"
      output << "}"
      output << "document.addEventListener('DOMContentLoaded', function(){ document.getElementById('childCreationModalShow').style.display='block'; });"
      output << "</script>"

      output.html_safe
    end
  end
end
