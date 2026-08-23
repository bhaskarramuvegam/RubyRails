# Redmine Parent to Child Update - Hooks

module RedmineParentToChildUpdate
  class Hooks < Redmine::Hook::ViewListener

    # ─── 1. NEW-ISSUE FORM ────────────────────────────────────────────────────
    # We only inject the shared CSS here.  The blocking form-level popup has been
    # removed because it was unreliable: the popup HTML was rendered based on the
    # tracker selected at page-load time, so it never appeared when the user
    # switched to a CR tracker after the form loaded.  All child-creation is now
    # handled by the show-page popup (hook #3 below).
    def view_issues_form_details_bottom(context = {})
      issue = context[:issue]
      return unless issue.parent_child_update_enabled?
      return if issue.parent_id.present?

      css = <<~CSS
        <style type='text/css'>
          .child-creation-modal { display:none; position:fixed; z-index:9999; left:0; top:0;
            width:100%; height:100%; background-color:rgba(0,0,0,0.5); font-family:Arial,sans-serif; }
          .child-creation-content { background:#fff; margin:6% auto; padding:24px;
            border:1px solid #888; width:540px; max-width:95%; border-radius:5px;
            box-shadow:0 4px 12px rgba(0,0,0,0.2); max-height:85vh; overflow-y:auto; }
          .child-creation-content h3 { margin-top:0; color:#333; }
          .child-creation-content label { font-weight:bold; }
          .child-creation-buttons { text-align:center; margin-top:20px; }
          .child-creation-buttons button { padding:10px 22px; margin:0 6px; font-size:14px;
            border-radius:3px; cursor:pointer; }
          .child-creation-buttons button.yes-btn { background:#4CAF50; color:#fff; border-color:#45a049; }
          .child-creation-buttons button.yes-btn:hover { background:#45a049; }
          .child-creation-buttons button.no-btn { background:#f44336; color:#fff; border-color:#da190b; }
          .child-creation-buttons button.no-btn:hover { background:#da190b; }
          .child-req-field { margin-bottom:12px; }
          .child-req-field label { display:block; font-size:13px; margin-bottom:4px; color:#444; }
          .child-req-field input, .child-req-field select {
            width:100%; padding:7px; font-size:13px; box-sizing:border-box; }
          .pcu-subtask-btn { display:inline-flex; align-items:center; gap:2px;
            background:none; color:#1976D2 !important; border:none; border-radius:0;
            padding:0; font-size:0.9em; cursor:pointer; text-decoration:none !important;
            margin-right:8px; vertical-align:middle; white-space:nowrap; font-weight:bold; }
          .pcu-subtask-btn:hover { color:#0d47a1 !important; text-decoration:underline !important; }
        </style>
      CSS
      css.html_safe
    end

    # ─── 2. AFTER NEW ISSUE SAVED ─────────────────────────────────────────────
    # Schedule the show-page popup only for CR-type issues.
    # We no longer process create_child / create_additional_tasks params here
    # because child creation now happens via AJAX from the show-page popup —
    # that path supports required custom fields and gives the user proper feedback.
    def controller_issues_new_after_save(context = {})
      issue      = context[:issue]
      controller = context[:controller]

      return unless issue.persisted?
      return unless issue.parent_child_update_enabled?
      return unless issue.tracker
      # Never auto-popup for issues that already have a parent (child issues)
      return if issue.parent_id.present?
      # Only schedule popup for hardcoded parent-tracker types
      return unless %w[change\ request user\ story].any? { |n| n.casecmp?(issue.tracker.name) }
      return unless controller && controller.session

      controller.session[:redmine_parent_to_child_show_prompt_for] = issue.id.to_i

      debug_logging = begin
        Setting.plugin_redmine_parent_to_child_update['enable_logging'] == '1'
      rescue
        false
      end
      Rails.logger.info("Parent to Child: Scheduled show-page popup for issue ##{issue.id}") if debug_logging
    end

    # ─── 3. ISSUE SHOW PAGE ───────────────────────────────────────────────────
    # Renders the child-creation modal on EVERY issue show page (hidden by default).
    # Opens two ways:
    #   a) Auto-open after CR creation (session key set in hook #2)
    #   b) User clicks "➕ Create Child" button injected next to Redmine's "+ ADD"
    def view_issues_show_details_bottom(context = {})
      issue      = context[:issue]
      controller = context[:controller]

      return unless issue.parent_child_update_enabled?
      return unless controller && controller.session
      return unless User.current.allowed_to?(:add_issues, issue.project)

      # ── Auto-open flag — consume session key BEFORE any early returns ────────
      # Must delete here so the key is never left dangling if we return early.
      scheduled_id = controller.session.delete(:redmine_parent_to_child_show_prompt_for)
      auto_open    = scheduled_id.to_i == issue.id.to_i

      # ── Filter tracker dropdown by per-parent-tracker plugin setting ─────────
      trackers_map    = Setting.plugin_redmine_parent_to_child_update['popup_child_trackers_by_parent'] || {}
      child_filter    = trackers_map[issue.tracker.id.to_s].to_s
                          .split(',').map(&:strip).reject(&:empty?)
      trackers = issue.available_child_trackers
      trackers = trackers.select { |t| child_filter.any? { |n| n.casecmp(t.name) == 0 } } if child_filter.any?
      return if trackers.empty? && !auto_open

      safe_subject      = ERB::Util.html_escape(issue.subject.to_s)
      safe_tracker_name = ERB::Util.html_escape(issue.tracker.name.to_s)

      output = +""

      # ── Modal CSS (must be on show page — form-hook CSS is not injected here) ──
      output << "<style type='text/css'>"
      output << "#pcu-child-modal{"
      output << "  display:none;position:fixed;z-index:99999;left:0;top:0;"
      output << "  width:100%;height:100%;background:rgba(0,0,0,0.55);"
      output << "  font-family:Arial,sans-serif;overflow-y:auto;}"
      output << "#pcu-child-modal .pcu-modal-box{"
      output << "  background:#fff;margin:1% auto;padding:0;"
      output << "  border-radius:6px;width:1340px;max-width:98%;"
      output << "  box-shadow:0 6px 24px rgba(0,0,0,0.25);max-height:97vh;overflow-y:auto;}"
      output << ".pcu-modal-header{"
      output << "  display:flex;align-items:center;justify-content:space-between;"
      output << "  padding:12px 20px 10px;border-bottom:1px solid #eee;}"
      output << ".pcu-modal-header h3{margin:0;color:#333;font-size:15px;}"
      output << ".pcu-modal-close-x{background:none;border:none;font-size:18px;cursor:pointer;"
      output << "  color:#888;line-height:1;padding:0 2px;} .pcu-modal-close-x:hover{color:#333;}"
      output << ".pcu-modal-body{padding:12px 20px;}"
      output << "#pcu-child-modal .pcu-desc{color:#666;font-size:12px;margin-bottom:10px;}"
      # Top section: tracker + subject side by side
      output << ".pcu-top-row{display:grid;grid-template-columns:1fr 2fr;gap:12px;margin-bottom:10px;}"
      # Fields grid: 3 columns for compact layout
      output << "#pcu-required-fields{display:grid;grid-template-columns:repeat(4,1fr);gap:10px 14px;"
      output << "  align-items:start;}"
      # Override: text/textarea fields span full width
      output << "#pcu-required-fields .pcu-field-full{grid-column:1/-1;}"
      output << "#pcu-child-modal label{font-weight:bold;font-size:12px;display:block;margin-bottom:3px;}"
      output << "#pcu-child-modal select,#pcu-child-modal input[type=text],#pcu-child-modal input[type=number],#pcu-child-modal input[type=date]{"
      output << "  width:100%;padding:5px 8px;font-size:12px;box-sizing:border-box;"
      output << "  border:1px solid #ccc;border-radius:3px;margin-top:2px;height:30px;}"
      output << ".pcu-field-block{margin-bottom:0;}"
      output << ".child-req-field{margin-bottom:0;}"
      output << ".child-req-field label{font-size:12px;font-weight:bold;color:#333;margin-bottom:3px;display:block;}"
      output << ".child-req-field input,.child-req-field select,.child-req-field textarea{"
      output << "  width:100%;padding:5px 8px;font-size:12px;box-sizing:border-box;"
      output << "  border:1px solid #ccc;border-radius:3px;height:30px;}"
      output << ".child-req-field textarea{height:80px;resize:vertical;}"
      # jsToolBar wrapper must stay within the modal width
      output << "#pcu-child-modal .jstBlock{width:100%;box-sizing:border-box;}"
      output << "#pcu-child-modal .jstEditor{width:100% !important;}"
      output << "#pcu-child-modal .jstEditor textarea{height:80px;width:100% !important;box-sizing:border-box;}"
      output << "#pcu-child-modal input[type=number]{-moz-appearance:textfield;appearance:textfield;}"
      output << "#pcu-child-modal input[type=number]::-webkit-outer-spin-button,"
      output << "#pcu-child-modal input[type=number]::-webkit-inner-spin-button{-webkit-appearance:none;margin:0;}"
      output << "#pcu-status-msg{display:none;margin:8px 0;padding:7px;border-radius:3px;font-size:12px;}"
      output << ".pcu-files-row{margin-top:8px;padding-top:8px;border-top:1px solid #f0f0f0;}"
      output << ".pcu-modal-footer{padding:10px 20px;border-top:1px solid #eee;"
      output << "  display:flex;gap:8px;flex-wrap:wrap;align-items:center;}"
      output << ".pcu-btn{padding:7px 16px;font-size:13px;border-radius:4px;cursor:pointer;border:none;font-weight:bold;}"
      output << ".pcu-btn-save{background:#4CAF50;color:#fff;} .pcu-btn-save:hover{background:#43a047;}"
      output << ".pcu-btn-save-child{background:#1976D2;color:#fff;} .pcu-btn-save-child:hover{background:#1565C0;}"
      output << ".pcu-btn-clear{background:#ff9800;color:#fff;} .pcu-btn-clear:hover{background:#fb8c00;}"
      output << ".pcu-btn-close{background:#9e9e9e;color:#fff;} .pcu-btn-close:hover{background:#757575;}"
      output << ".pcu-subtask-btn{display:inline-flex;align-items:center;gap:2px;"
      output << "  background:none;color:#1976D2 !important;border:none;border-radius:0;"
      output << "  padding:0;font-size:0.9em;cursor:pointer;text-decoration:none !important;"
      output << "  margin-right:8px;vertical-align:middle;white-space:nowrap;font-weight:bold;}"
      output << ".pcu-subtask-btn:hover{color:#0d47a1 !important;text-decoration:underline !important;}"
      output << "</style>"

      # Trackers that have children configured → show "Save & Create Child Tracker" button
      trackers_with_children = (Setting.plugin_redmine_parent_to_child_update['popup_child_trackers_by_parent'] || {})
                                 .select { |_, v| v.to_s.strip.present? }.keys.map(&:to_s)
      # Hardcoded parent tracker names — these always get "Save & Create Child Tracker" button
      popup_parent_names_set = %w[change\ request user\ story]
      # Current issue is itself a parent tracker → always show chain buttons
      current_is_parent = popup_parent_names_set.any? { |n| n.casecmp?(issue.tracker.name) }

      # JS map: tracker_id => { hasChildren, isTerminal }
      tracker_has_children_js = trackers.map { |t|
        is_terminal = !popup_parent_names_set.include?(t.name.downcase)
        "\"#{t.id}\":{c:#{trackers_with_children.include?(t.id.to_s)},term:#{is_terminal}}"
      }.join(',')
      # JS map: tracker_id => tracker_name (for display)
      tracker_names_js = trackers.map { |t|
        "\"#{t.id}\":#{t.name.to_json}"
      }.join(',')

      # ── Modal HTML (always rendered, hidden by default) ────────────────────
      output << "<div id='pcu-child-modal'>"
      output << "  <div class='pcu-modal-box'>"

      # Header with X close button
      output << "  <div class='pcu-modal-header'>"
      output << "    <h3>Create Child Tracker</h3>"
      output << "    <button type='button' class='pcu-modal-close-x' onclick='pcuCloseModal()' title='Close'>&#10005;</button>"
      output << "  </div>"

      # Body
      output << "  <div class='pcu-modal-body'>"
      output << "    <p class='pcu-desc'>Create a child tracker under <strong>#{safe_tracker_name} ##{issue.id} &ndash; #{safe_subject}</strong>.</p>"

      # Tracker type + Subject in a 2-column top row
      output << "    <div class='pcu-top-row'>"
      output << "      <div class='pcu-field-block'>"
      output << "        <label for='pcu-tracker-select'>Child tracker type <span style='color:red'>*</span></label>"
      output << "        <select id='pcu-tracker-select' onchange='pcuOnTrackerChange(#{issue.id})'>"
      trackers.each_with_index do |t, i|
        output << "          <option value='#{t.id}'#{i == 0 ? ' selected' : ''}>#{ERB::Util.html_escape(t.name)}</option>"
      end
      output << "        </select>"
      output << "      </div>"
      output << "      <div class='pcu-field-block'>"
      output << "        <label for='pcu-subject'>Tracker subject <span style='color:red'>*</span></label>"
      output << "        <input type='text' id='pcu-subject' value='#{safe_subject}' placeholder='Enter tracker subject'>"
      output << "      </div>"
      output << "    </div>"

      # Dynamic fields — rendered in 3-column grid by CSS; text/textarea fields span full width via JS
      output << "    <div id='pcu-required-fields'></div>"

      # File upload — full-width row below the fields grid
      max_size_kb = Setting.attachment_max_size.to_i rescue 5120
      max_size_mb = (max_size_kb / 1024.0).round(1)
      output << "    <div class='pcu-files-row'>"
      output << "      <label for='pcu-files' style='font-size:12px;font-weight:bold;margin-bottom:3px;display:block;'>Files</label>"
      output << "      <div style='display:flex;align-items:center;gap:12px;'>"
      output << "        <input type='file' id='pcu-files' multiple style='font-size:12px;'>"
      output << "        <span style='color:#888;font-size:11px;'>Max #{max_size_mb} MB per file</span>"
      output << "      </div>"
      output << "    </div>"

      output << "    <div id='pcu-status-msg'></div>"
      output << "  </div>"

      # Footer buttons
      output << "  <div class='pcu-modal-footer'>"
      output << "    <button type='button' class='pcu-btn pcu-btn-save' id='pcu-btn-save'"
      output << "            onclick='pcuSubmit(#{issue.id},false)'>Save Tracker</button>"
      output << "    <button type='button' class='pcu-btn pcu-btn-save-child' id='pcu-btn-save-child'"
      output << "            onclick='pcuSubmit(#{issue.id},true)' style='display:none'>Save &amp; Create Child Tracker</button>"
      output << "    <button type='button' class='pcu-btn pcu-btn-clear'"
      output << "            onclick='pcuClearFields()'>Clear</button>"
      output << "    <button type='button' class='pcu-btn pcu-btn-close'"
      output << "            onclick='pcuCloseModal()'>Close</button>"
      output << "  </div>"
      output << "  </div>"
      output << "</div>"

      # ── JavaScript ────────────────────────────────────────────────────────
      output << "<script type='text/javascript'>"

      output << "var pcuTrackerInfo={#{tracker_has_children_js}};"
      output << "var pcuTrackerNames={#{tracker_names_js}};"
      # Legacy alias — keeps any other code that references this working
      output << "var pcuTrackerHasChildren={};"
      output << "Object.keys(pcuTrackerInfo).forEach(function(k){pcuTrackerHasChildren[k]=pcuTrackerInfo[k].c;});"

      output << "function pcuCsrfToken(){"
      output << "  var m=document.querySelector('meta[name=csrf-token]');"
      output << "  if(m) return m.getAttribute('content');"
      output << "  var i=document.querySelector('input[name=authenticity_token]');"
      output << "  return i?i.value:null;"
      output << "}"

      # Close and fully reset the modal
      output << "function pcuCloseModal(){"
      output << "  document.getElementById('pcu-child-modal').style.display='none';"
      output << "  document.getElementById('pcu-required-fields').innerHTML='';"
      output << "  var msg=document.getElementById('pcu-status-msg');"
      output << "  if(msg){msg.style.display='none';msg.textContent='';}"
      output << "  document.getElementById('pcu-btn-save').disabled=false;"
      output << "  var sc=document.getElementById('pcu-btn-save-child');"
      output << "  if(sc) sc.disabled=false;"
      output << "}"

      # Clear all editable fields in the popup (reset to blank / first option)
      output << "function pcuClearFields(){"
      output << "  document.getElementById('pcu-subject').value='';"
      output << "  document.querySelectorAll('#pcu-required-fields .pcu-req-cf').forEach(function(inp){"
      output << "    if(inp.tagName==='SELECT') inp.selectedIndex=0;"
      output << "    else inp.value='';"
      output << "  });"
      output << "  var fi=document.getElementById('pcu-files');"
      output << "  if(fi) fi.value='';"
      output << "  var msg=document.getElementById('pcu-status-msg');"
      output << "  if(msg){msg.style.display='none';msg.textContent='';}"
      output << "}"

      # Update buttons and load fields when tracker changes
      output << "function pcuOnTrackerChange(parentId){"
      output << "  var tid=document.getElementById('pcu-tracker-select').value;"
      output << "  var info=pcuTrackerInfo[tid]||{c:false,term:true};"
      output << "  var sc=document.getElementById('pcu-btn-save-child');"
      output << "  var saveBtn=document.getElementById('pcu-btn-save');"
      output << "  var closeBtn=document.getElementById('pcu-btn-close');"
      # Show "Save & Create Child" only when current issue is a parent tracker AND
      # the selected child tracker is also a chain parent (not terminal, e.g. User Story).
      # When Task is selected (terminal), hide the button.
      if current_is_parent
        output << "  var showChain=!info.term;"
        output << "  if(sc) sc.style.display=(showChain?'':'none');"
        output << "  if(saveBtn) saveBtn.textContent='Save Tracker';"
        output << "  if(closeBtn) closeBtn.textContent=(showChain?'Close':'Cancel');"
      else
        output << "  if(sc) sc.style.display='none';"
        output << "  if(saveBtn) saveBtn.textContent='Save';"
        output << "  if(closeBtn) closeBtn.textContent='Cancel';"
      end
      output << "  pcuLoadRequiredFields(parentId);"
      output << "}"

      # Load admin-configured popup fields for selected tracker
      output << "function pcuLoadRequiredFields(parentId){"
      output << "  var tid=document.getElementById('pcu-tracker-select').value;"
      output << "  var box=document.getElementById('pcu-required-fields');"
      output << "  box.innerHTML='';"
      output << "  if(!tid) return;"
      output << "  fetch('/redmine_parent_to_child_update/child_issues/required_fields/'+parentId+'?tracker_id='+tid,{"
      output << "    headers:{'X-Requested-With':'XMLHttpRequest','Accept':'application/json'},"
      output << "    credentials:'same-origin'"
      output << "  }).then(function(r){"
      output << "    if(!r.ok) return r.json().then(function(j){throw new Error(j.error||('HTTP '+r.status));});"
      output << "    return r.json();"
      output << "  })"
      output << "  .then(function(json){"
      output << "    if(json.error){ pcuShowStatus('Could not load fields: '+json.error,'#fdecea','#c62828'); return; }"
      output << "    if(!json.fields||json.fields.length===0) return;"
      output << "    json.fields.forEach(function(cf){"
      # text/textarea fields span all 3 columns; everything else fits in one column
      output << "      var isWide=(cf.field_format==='text');"
      output << "      var w=document.createElement('div');"
      output << "      w.className='child-req-field'+(isWide?' pcu-field-full':'');"
      output << "      var lb=document.createElement('label');"
      output << "      var badge=cf.is_standard"
      output << "        ? '<span style=\"font-size:10px;background:#1976D2;color:#fff;border-radius:3px;padding:1px 4px;margin-left:4px;\">std</span>'"
      output << "        : (cf.is_required"
      output << "          ? '<span style=\"font-size:10px;background:#f44336;color:#fff;border-radius:3px;padding:1px 4px;margin-left:4px;\">req</span>'"
      output << "          : '');"
      output << "      lb.innerHTML=cf.name+badge; w.appendChild(lb);"
      output << "      var initVal=(cf.value&&cf.value.trim()!=='')?cf.value:(cf.default_value||'');"
      output << "      var inp;"
      # 'select' = standard fields with dynamic options (user, priority, category, version)
      output << "      if(cf.field_format==='select'&&cf.possible_values.length>0){"
      output << "        inp=document.createElement('select');"
      output << "        var bk=document.createElement('option'); bk.value=''; bk.textContent='-- Select --'; inp.appendChild(bk);"
      output << "        cf.possible_values.forEach(function(pv){"
      output << "          var o=document.createElement('option');"
      output << "          o.value=pv.value||pv; o.textContent=pv.label||pv;"
      output << "          if(o.value===initVal) o.selected=true; inp.appendChild(o);"
      output << "        });"
      # 'list' = custom fields with static options
      output << "      } else if(cf.field_format==='list'&&cf.possible_values.length>0){"
      output << "        inp=document.createElement('select');"
      output << "        var bk=document.createElement('option'); bk.value=''; bk.textContent='-- Select --'; inp.appendChild(bk);"
      output << "        cf.possible_values.forEach(function(v){"
      output << "          var o=document.createElement('option'); o.value=v; o.textContent=v;"
      output << "          if(v===initVal) o.selected=true; inp.appendChild(o);"
      output << "        });"
      output << "      } else if(cf.field_format==='bool'){"
      output << "        inp=document.createElement('select');"
      output << "        [['','-- Select --'],['0','No'],['1','Yes']].forEach(function(p){"
      output << "          var o=document.createElement('option'); o.value=p[0]; o.textContent=p[1];"
      output << "          if(p[0]===initVal) o.selected=true; inp.appendChild(o);"
      output << "        });"
      output << "      } else if(cf.field_format==='date'){"
      output << "        inp=document.createElement('input'); inp.type='date';"
      output << "        if(initVal) inp.value=initVal;"
      output << "      } else if(cf.field_format==='float'){"
      output << "        inp=document.createElement('input'); inp.type='number'; inp.step='0.01';"
      output << "        if(initVal) inp.value=initVal;"
      output << "      } else if(cf.field_format==='int'){"
      output << "        inp=document.createElement('input'); inp.type='number';"
      output << "        if(initVal) inp.value=initVal;"
      output << "      } else if(cf.field_format==='text'){"
      output << "        inp=document.createElement('textarea'); inp.rows=3;"
      output << "        inp.style.cssText='width:100%;padding:5px 8px;font-size:12px;box-sizing:border-box;min-height:80px;resize:vertical;';"
      output << "        if(cf.is_standard&&cf.std_key==='description') inp.id='pcu-desc-textarea';"
      output << "        if(initVal) inp.value=initVal;"
      output << "      } else {"
      output << "        inp=document.createElement('input'); inp.type='text';"
      output << "        if(initVal) inp.value=initVal;"
      output << "      }"
      # Tag inputs with either std_key or cf_id so pcuCreateChild knows how to submit them
      output << "      if(cf.is_standard){ inp.dataset.stdKey=cf.std_key; } else { inp.dataset.cfId=cf.id; }"
      output << "      inp.dataset.required=cf.is_required?'1':'0';"
      output << "      if(cf.is_readonly){"
      output << "        inp.disabled=true;"
      output << "        inp.style.background='#f5f5f5';inp.style.color='#888';inp.style.cursor='not-allowed';"
      output << "        inp.title='Read-only (workflow permission)';"
      output << "      }"
      output << "      if(inp.type==='number'){inp.addEventListener('wheel',function(e){e.preventDefault();},{passive:false});}"
      output << "      inp.className='pcu-req-cf'; w.appendChild(inp); box.appendChild(w);"
      output << "    });"
      # Initialise Redmine's wiki toolbar on the description textarea if available.
      # jsToolBar is already loaded on issue pages; we call it after a short delay so
      # the textarea is fully in the DOM before the toolbar wraps it.
      output << "    setTimeout(function(){"
      output << "      var descTa=document.getElementById('pcu-desc-textarea');"
      output << "      if(descTa&&typeof jsToolBar!=='undefined'&&!descTa.dataset.tbInit){"
      output << "        descTa.dataset.tbInit='1';"
      output << "        try{"
      output << "          var tb=new jsToolBar(descTa);"
      output << "          if(tb.setHelpLink) tb.setHelpLink('');"
      output << "          tb.draw();"
      output << "        }catch(e){}"
      output << "      }"
      output << "    },80);"
      output << "  }).catch(function(err){ pcuShowStatus('Field load failed: '+err.message,'#fdecea','#c62828'); });"
      output << "}"

      # Submit: withChain=true → Save & Create Child Tracker; false → Save Tracker only
      output << "function pcuSubmit(parentId,withChain){"
      output << "  var tracker=document.getElementById('pcu-tracker-select').value;"
      output << "  var subject=document.getElementById('pcu-subject').value.trim();"
      output << "  if(!tracker){alert('Please select a child tracker type.');return;}"
      output << "  if(!subject){alert('Please enter a tracker subject.');return;}"
      output << "  var cfInputs=document.querySelectorAll('#pcu-required-fields .pcu-req-cf');"
      output << "  for(var i=0;i<cfInputs.length;i++){"
      output << "    if(cfInputs[i].disabled) continue;"
      output << "    if(cfInputs[i].dataset.required!=='1') continue;"
      output << "    if(!cfInputs[i].value||cfInputs[i].value.trim()===''){"
      output << "      var lbl=cfInputs[i].closest('.child-req-field');"
      output << "      var fn=lbl?lbl.querySelector('label').textContent.trim():'A required field';"
      output << "      alert(fn+' cannot be blank.'); cfInputs[i].focus(); return;"
      output << "    }"
      output << "  }"
      output << "  var token=pcuCsrfToken();"
      output << "  if(!token){alert('CSRF token not found. Please reload.');return;}"
      output << "  var saveBtn=document.getElementById('pcu-btn-save');"
      output << "  var saveChildBtn=document.getElementById('pcu-btn-save-child');"
      output << "  saveBtn.disabled=true;"
      output << "  if(saveChildBtn) saveChildBtn.disabled=true;"
      output << "  var data=new FormData();"
      output << "  data.append('tracker_id',tracker);"
      output << "  data.append('subject',subject);"
      output << "  data.append('skip_chain',withChain?'0':'1');"
      output << "  var fileInput=document.getElementById('pcu-files');"
      output << "  if(fileInput&&fileInput.files.length>0){"
      output << "    for(var fi=0;fi<fileInput.files.length;fi++){"
      output << "      data.append('attachments['+fi+'][file]',fileInput.files[fi]);"
      output << "      data.append('attachments['+fi+'][filename]',fileInput.files[fi].name);"
      output << "    }"
      output << "  }"
      output << "  cfInputs.forEach(function(inp){"
      output << "    if(inp.disabled) return;"
      output << "    if(inp.dataset.stdKey&&inp.value){"
      output << "      data.append('std_fields['+inp.dataset.stdKey+']',inp.value);"
      output << "    } else if(inp.dataset.cfId&&inp.value){"
      output << "      data.append('custom_field_values['+inp.dataset.cfId+']',inp.value);"
      output << "    }"
      output << "  });"
      output << "  fetch('/redmine_parent_to_child_update/child_issues/create/'+parentId,{"
      output << "    method:'POST',"
      output << "    headers:{'X-CSRF-Token':token,'X-Requested-With':'XMLHttpRequest','Accept':'application/json'},"
      output << "    body:data,credentials:'same-origin'"
      output << "  }).then(function(r){"
      output << "    return r.text().then(function(t){"
      output << "      if(!r.ok){try{var j=JSON.parse(t);throw new Error(j.error||t);}catch(e){throw new Error(t);}}"
      output << "      return JSON.parse(t);"
      output << "    });"
      output << "  }).then(function(json){"
      output << "    if(json.error){"
      output << "      pcuShowStatus(json.error,'#fdecea','#c62828');"
      output << "      saveBtn.disabled=false;"
      output << "      if(saveChildBtn) saveChildBtn.disabled=false;"
      output << "    } else if(json.redirect_to){"
      output << "      pcuShowStatus('Tracker created! Loading child creation...','#e8f5e9','#2e7d32');"
      output << "      setTimeout(function(){window.location.href=json.redirect_to;},900);"
      output << "    } else {"
      output << "      pcuShowStatus('Tracker created successfully!','#e8f5e9','#2e7d32');"
      output << "      setTimeout(function(){window.location.reload();},1200);"
      output << "    }"
      output << "  }).catch(function(err){"
      output << "    pcuShowStatus(err.message,'#fdecea','#c62828');"
      output << "    saveBtn.disabled=false;"
      output << "    if(saveChildBtn) saveChildBtn.disabled=false;"
      output << "  });"
      output << "}"

      output << "function pcuShowStatus(msg,bg,color){"
      output << "  var el=document.getElementById('pcu-status-msg');"
      output << "  el.style.display='block'; el.style.background=bg; el.style.color=color; el.textContent=msg;"
      output << "}"

      # Inject ➕ Create Child button immediately before Redmine's + ADD subtask link
      output << "function pcuInjectSubtaskButton(issueId){"
      output << "  if(document.getElementById('pcu-add-btn-'+issueId)) return;"
      # Find Redmine's native subtask "+ ADD" anchor — href contains parent_issue_id=<id>
      output << "  var addLink=null;"
      output << "  var anchors=document.querySelectorAll('a');"
      output << "  for(var i=0;i<anchors.length;i++){"
      output << "    var h=anchors[i].href||'';"
      output << "    if((h.indexOf('parent_issue_id='+issueId)!==-1||"
      output << "        h.indexOf('parent_issue_id%5D='+issueId)!==-1||"
      output << "        h.indexOf('%5Bparent_issue_id%5D='+issueId)!==-1)&&"
      output << "       (anchors[i].className.indexOf('icon-add')!==-1||"
      output << "        /\\/issues\\/new/i.test(h))){"
      output << "      addLink=anchors[i]; break;"
      output << "    }"
      output << "  }"
      # Fallback: find icon-add anchor near a subtask table
      output << "  if(!addLink){"
      output << "    var tbl=document.getElementById('issue_tree')||document.querySelector('table.issues.subtasks');"
      output << "    if(tbl){"
      output << "      var lk=tbl.querySelector('a.icon-add')||tbl.previousElementSibling&&tbl.previousElementSibling.querySelector('a.icon-add');"
      output << "      if(lk) addLink=lk;"
      output << "    }"
      output << "  }"
      output << "  if(!addLink) return;"
      output << "  var btn=document.createElement('a');"
      output << "  btn.id='pcu-add-btn-'+issueId;"
      output << "  btn.href='#';"
      output << "  btn.className='pcu-subtask-btn';"
      output << "  btn.title='Create child issue via popup';"
      output << "  btn.innerHTML='CREATE CHILD';"
      output << "  btn.addEventListener('click',function(e){"
      output << "    e.preventDefault();"
      output << "    pcuCloseModal();"
      output << "    document.getElementById('pcu-child-modal').style.display='block';"
      output << "    pcuOnTrackerChange(issueId);"
      output << "  });"
      output << "  addLink.parentNode.insertBefore(btn,addLink);"
      # Make the parent container always visible (Redmine hides it until hover)
      output << "  var container=addLink.parentNode;"
      output << "  while(container&&container!==document.body){"
      output << "    var cs=window.getComputedStyle(container);"
      output << "    if(cs.display==='none'||cs.visibility==='hidden'||cs.opacity==='0'){"
      output << "      container.style.cssText+='display:block!important;visibility:visible!important;opacity:1!important;';"
      output << "    }"
      output << "    if(container.className&&(container.className.indexOf('contextual')!==-1||container.className.indexOf('links')!==-1)) {"
      output << "      container.style.cssText+='display:block!important;visibility:visible!important;opacity:1!important;';"
      output << "      break;"
      output << "    }"
      output << "    container=container.parentNode;"
      output << "  }"
      output << "}"

      # Move modal to <body> and auto-open for CR flow.
      # Use readyState check instead of just DOMContentLoaded: with Turbolinks/Hotwire
      # navigation DOMContentLoaded may already have fired when this inline script runs,
      # so the listener would never be called. Calling immediately when readyState is
      # already 'interactive' or 'complete' handles both cases.
      output << "(function(){"
      output << "  function pcuInitModal(){"
      output << "    var modal=document.getElementById('pcu-child-modal');"
      output << "    if(!modal) return;"
      output << "    if(modal.parentNode!==document.body) document.body.appendChild(modal);"
      if auto_open
        output << "    modal.style.display='block';"
        output << "    pcuOnTrackerChange(#{issue.id});"
      end
      output << "    pcuInjectSubtaskButton(#{issue.id});"
      output << "  }"
      output << "  if(document.readyState==='loading'){"
      output << "    document.addEventListener('DOMContentLoaded',pcuInitModal);"
      output << "  } else { pcuInitModal(); }"
      output << "})();"

      output << "</script>"
      output.html_safe
    end

  end
end
