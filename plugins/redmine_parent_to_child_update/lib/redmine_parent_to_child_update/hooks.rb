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
          .child-creation-modal { display:none; position:fixed; z-index:1000; left:0; top:0;
            width:100%; height:100%; background-color:rgba(0,0,0,0.5); font-family:Arial,sans-serif; }
          .child-creation-content { background:#fff; margin:8% auto; padding:24px;
            border:1px solid #888; width:520px; max-width:95%; border-radius:5px;
            box-shadow:0 4px 12px rgba(0,0,0,0.2); max-height:80vh; overflow-y:auto; }
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
      # Only schedule popup for configured parent-tracker types (e.g. Change Request)
      return unless issue.popup_parent_tracker_names.any? { |n| n.casecmp?(issue.tracker.name) }
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
    # Renders the child-creation popup immediately after a CR is first viewed
    # following its creation.  The popup:
    #   • lets the user pick a child tracker
    #   • fetches required custom fields missing from the parent (via AJAX)
    #   • creates the child via AJAX (no page reload needed for the POST itself)
    def view_issues_show_details_bottom(context = {})
      issue      = context[:issue]
      controller = context[:controller]

      return unless issue.parent_child_update_enabled?
      return unless controller && controller.session

      scheduled_id = controller.session.delete(:redmine_parent_to_child_show_prompt_for)
      # Session may serialise the integer as a String — compare both sides as integers
      return unless scheduled_id.to_i == issue.id.to_i

      popup_filter = Setting.plugin_redmine_parent_to_child_update['popup_child_trackers'].to_s
                       .split(',').map(&:strip).reject(&:empty?)
      trackers = issue.available_child_trackers
      trackers = trackers.select { |t| popup_filter.any? { |n| n.casecmp(t.name) == 0 } } if popup_filter.any?
      first_tracker_id = trackers.first&.id.to_i

      output = +""

      # ── modal HTML ──────────────────────────────────────────────────────────
      output << "<div id='pcu-child-modal' class='child-creation-modal'>"
      output << "  <div class='child-creation-content'>"
      output << "    <h3>Create Child Issue</h3>"
      output << "    <p style='color:#666;'>This <strong>#{issue.tracker.name}</strong> was just created. "
      output << "Would you like to create a child issue? It will inherit fields from this issue.</p>"

      output << "    <div style='margin:14px 0;'>"
      output << "      <label for='pcu-tracker-select'>Child issue type <span style='color:red'>*</span></label>"
      output << "      <select id='pcu-tracker-select' style='width:100%;margin-top:5px;padding:7px;font-size:13px;'"
      output << "              onchange='pcuLoadRequiredFields(#{issue.id})'>"
      trackers.each_with_index do |t, i|
        output << "        <option value='#{t.id}'#{i == 0 ? " selected" : ""}>#{t.name}</option>"
      end
      output << "      </select>"
      output << "    </div>"

      output << "    <div style='margin:14px 0;'>"
      output << "      <label for='pcu-subject'>Child subject <span style='color:red'>*</span></label>"
      output << "      <input type='text' id='pcu-subject'"
      output << "             style='width:100%;margin-top:5px;padding:7px;font-size:13px;box-sizing:border-box;'"
      output << "             value='#{issue.subject.to_s.gsub("'", '&#39;').gsub('"', '&quot;')}'>"
      output << "    </div>"

      output << "    <div id='pcu-required-fields'></div>"

      if issue.additional_child_trackers.any?
        output << "    <div style='margin:14px 0;'>"
        output << "      <label>Also create additional child issues:</label>"
        issue.additional_child_trackers.each do |t|
          output << "      <div style='margin-top:6px;'>"
          output << "        <label><input type='checkbox' class='pcu-extra-tracker' value='#{t.id}'> #{t.name}</label>"
          output << "      </div>"
        end
        output << "    </div>"
      end

      output << "    <div id='pcu-status-msg' style='display:none;margin:10px 0;padding:8px;"
      output << "         border-radius:3px;font-size:13px;'></div>"

      output << "    <div class='child-creation-buttons'>"
      output << "      <button type='button' class='yes-btn' id='pcu-submit-btn'"
      output << "              onclick='pcuCreateChild(#{issue.id})'>Yes, Create Child</button>"
      output << "      <button type='button' class='no-btn'"
      output << "              onclick='document.getElementById(\"pcu-child-modal\").style.display=\"none\"'>No</button>"
      output << "    </div>"
      output << "  </div>"
      output << "</div>"

      # ── JavaScript ──────────────────────────────────────────────────────────
      output << "<script type='text/javascript'>"

      output << "function pcuCsrfToken(){"
      output << "  var m=document.querySelector('meta[name=csrf-token]');"
      output << "  if(m) return m.getAttribute('content');"
      output << "  var i=document.querySelector('input[name=authenticity_token]');"
      output << "  return i?i.value:null;"
      output << "}"

      # Load required fields for selected tracker
      output << "function pcuLoadRequiredFields(parentId){"
      output << "  var tid=document.getElementById('pcu-tracker-select').value;"
      output << "  var box=document.getElementById('pcu-required-fields');"
      output << "  box.innerHTML='';"
      output << "  if(!tid) return;"
      output << "  fetch('/redmine_parent_to_child_update/child_issues/required_fields/'+parentId+'?tracker_id='+tid,{"
      output << "    headers:{'X-Requested-With':'XMLHttpRequest','Accept':'application/json'},"
      output << "    credentials:'same-origin'"
      output << "  }).then(function(r){return r.json();})"
      output << "  .then(function(json){"
      output << "    if(!json.fields||json.fields.length===0) return;"
      output << "    var hd=document.createElement('p');"
      output << "    hd.style.cssText='font-weight:bold;margin:14px 0 6px;color:#333;font-size:13px;border-top:1px solid #eee;padding-top:12px;';"
      output << "    hd.textContent='Additional fields for child issue:';"
      output << "    box.appendChild(hd);"
      output << "    json.fields.forEach(function(cf){"
      output << "      var w=document.createElement('div');"
      output << "      w.className='child-req-field';"
      # Label with required/optional badge
      output << "      var lb=document.createElement('label');"
      output << "      var badge=cf.is_required"
      output << "        ? '<span style=\"font-size:10px;background:#f44336;color:#fff;border-radius:3px;padding:1px 5px;margin-left:5px;\">required</span>'"
      output << "        : '<span style=\"font-size:10px;background:#888;color:#fff;border-radius:3px;padding:1px 5px;margin-left:5px;\">optional</span>';"
      output << "      lb.innerHTML=cf.name+badge;"
      output << "      w.appendChild(lb);"
      # Resolve the best initial value: parent value > default value > ''
      output << "      var initVal=(cf.value&&cf.value.trim()!=='')?cf.value:cf.default_value||'';"
      output << "      var inp;"
      output << "      if(cf.field_format==='list'&&cf.possible_values.length>0){"
      output << "        inp=document.createElement('select');"
      output << "        var bk=document.createElement('option'); bk.value=''; bk.textContent='-- Select --';"
      output << "        inp.appendChild(bk);"
      output << "        cf.possible_values.forEach(function(v){"
      output << "          var o=document.createElement('option'); o.value=v; o.textContent=v;"
      output << "          if(v===initVal) o.selected=true;"
      output << "          inp.appendChild(o);"
      output << "        });"
      output << "      } else if(cf.field_format==='bool'){"
      output << "        inp=document.createElement('select');"
      output << "        [['','-- Select --'],['0','No'],['1','Yes']].forEach(function(p){"
      output << "          var o=document.createElement('option'); o.value=p[0]; o.textContent=p[1];"
      output << "          if(p[0]===initVal) o.selected=true;"
      output << "          inp.appendChild(o);"
      output << "        });"
      output << "      } else if(cf.field_format==='date'){"
      output << "        inp=document.createElement('input'); inp.type='date';"
      output << "        if(initVal) inp.value=initVal;"
      output << "      } else if(cf.field_format==='int'||cf.field_format==='float'){"
      output << "        inp=document.createElement('input'); inp.type='number';"
      output << "        if(initVal) inp.value=initVal;"
      output << "      } else {"
      output << "        inp=document.createElement('input'); inp.type='text';"
      output << "        if(initVal) inp.value=initVal;"
      output << "      }"
      output << "      inp.dataset.cfId=cf.id;"
      output << "      inp.dataset.required=cf.is_required?'1':'0';"
      output << "      inp.className='pcu-req-cf';"
      output << "      w.appendChild(inp);"
      output << "      box.appendChild(w);"
      output << "    });"
      output << "  }).catch(function(){});"
      output << "}"

      # Create child via AJAX
      output << "function pcuCreateChild(parentId){"
      output << "  var tracker=document.getElementById('pcu-tracker-select').value;"
      output << "  var subject=document.getElementById('pcu-subject').value.trim();"
      output << "  if(!tracker){alert('Please select a child issue type.');return;}"
      output << "  if(!subject){alert('Please enter a subject for the child issue.');return;}"
      # Validate only fields marked as required (data-required="1")
      output << "  var cfInputs=document.querySelectorAll('.pcu-req-cf');"
      output << "  for(var i=0;i<cfInputs.length;i++){"
      output << "    if(cfInputs[i].dataset.required!=='1') continue;"
      output << "    if(!cfInputs[i].value||cfInputs[i].value.trim()===''){"
      output << "      var lbl=cfInputs[i].closest('.child-req-field');"
      output << "      var fn=lbl?lbl.querySelector('label').textContent.trim():'A required field';"
      output << "      alert(fn+' cannot be blank.'); cfInputs[i].focus(); return;"
      output << "    }"
      output << "  }"
      output << "  var token=pcuCsrfToken();"
      output << "  if(!token){alert('CSRF token not found. Please reload and try again.');return;}"
      output << "  var btn=document.getElementById('pcu-submit-btn');"
      output << "  btn.disabled=true; btn.textContent='Creating...';"
      output << "  var data=new FormData();"
      output << "  data.append('tracker_id',tracker);"
      output << "  data.append('subject',subject);"
      output << "  cfInputs.forEach(function(inp){"
      output << "    if(inp.dataset.cfId&&inp.value){"
      output << "      data.append('custom_field_values['+inp.dataset.cfId+']',inp.value);"
      output << "    }"
      output << "  });"
      output << "  document.querySelectorAll('.pcu-extra-tracker:checked').forEach(function(cb){"
      output << "    data.append('additional_child_tracker_ids[]',cb.value);"
      output << "  });"
      output << "  fetch('/redmine_parent_to_child_update/child_issues/create/'+parentId,{"
      output << "    method:'POST',"
      output << "    headers:{'X-CSRF-Token':token,'X-Requested-With':'XMLHttpRequest','Accept':'application/json'},"
      output << "    body:data, credentials:'same-origin'"
      output << "  }).then(function(r){"
      output << "    return r.text().then(function(t){"
      output << "      if(!r.ok){"
      output << "        try{var j=JSON.parse(t);throw new Error(j.error||t);}catch(e){throw new Error(t);}"
      output << "      }"
      output << "      return JSON.parse(t);"
      output << "    });"
      output << "  }).then(function(json){"
      output << "    if(json.error){"
      output << "      pcuShowStatus(json.error,'#fdecea','#c62828');"
      output << "      btn.disabled=false; btn.textContent='Yes, Create Child';"
      output << "    } else {"
      output << "      pcuShowStatus('Child issue created successfully! Reloading...','#e8f5e9','#2e7d32');"
      output << "      setTimeout(function(){ window.location.reload(); },1200);"
      output << "    }"
      output << "  }).catch(function(err){"
      output << "    pcuShowStatus(err.message,'#fdecea','#c62828');"
      output << "    btn.disabled=false; btn.textContent='Yes, Create Child';"
      output << "  });"
      output << "}"

      output << "function pcuShowStatus(msg,bg,color){"
      output << "  var el=document.getElementById('pcu-status-msg');"
      output << "  el.style.display='block'; el.style.background=bg; el.style.color=color;"
      output << "  el.textContent=msg;"
      output << "}"

      # Show popup on load and auto-fetch required fields for the first tracker
      output << "document.addEventListener('DOMContentLoaded',function(){"
      output << "  document.getElementById('pcu-child-modal').style.display='block';"
      if first_tracker_id > 0
        output << "  pcuLoadRequiredFields(#{issue.id});"
      end
      output << "});"

      output << "</script>"

      output.html_safe
    end

  end
end
