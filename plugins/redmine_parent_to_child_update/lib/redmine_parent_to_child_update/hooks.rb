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

      # ── Filter tracker dropdown by per-parent-tracker plugin setting ─────────
      trackers_map    = Setting.plugin_redmine_parent_to_child_update['popup_child_trackers_by_parent'] || {}
      child_filter    = trackers_map[issue.tracker.id.to_s].to_s
                          .split(',').map(&:strip).reject(&:empty?)
      trackers = issue.available_child_trackers
      trackers = trackers.select { |t| child_filter.any? { |n| n.casecmp(t.name) == 0 } } if child_filter.any?
      return if trackers.empty?

      # ── Auto-open flag (CR creation flow) ─────────────────────────────────
      scheduled_id = controller.session.delete(:redmine_parent_to_child_show_prompt_for)
      auto_open    = scheduled_id.to_i == issue.id.to_i

      safe_subject = ERB::Util.html_escape(issue.subject.to_s)

      output = +""

      # ── Modal CSS (must be on show page — form-hook CSS is not injected here) ──
      output << "<style type='text/css'>"
      output << "#pcu-child-modal{"
      output << "  display:none;position:fixed;z-index:99999;left:0;top:0;"
      output << "  width:100%;height:100%;background:rgba(0,0,0,0.55);"
      output << "  font-family:Arial,sans-serif;overflow-y:auto;}"
      output << "#pcu-child-modal .pcu-modal-box{"
      output << "  background:#fff;margin:2% auto;padding:32px 36px;"
      output << "  border-radius:5px;width:840px;max-width:95%;"
      output << "  box-shadow:0 6px 24px rgba(0,0,0,0.25);max-height:92vh;overflow-y:auto;}"
      output << "#pcu-child-modal h3{margin:0 0 8px;color:#333;font-size:20px;}"
      output << "#pcu-child-modal .pcu-desc{color:#666;font-size:16px;margin-bottom:20px;}"
      output << "#pcu-child-modal label{font-weight:bold;font-size:16px;display:block;margin-bottom:6px;}"
      output << "#pcu-child-modal select,#pcu-child-modal input[type=text],#pcu-child-modal input[type=number],#pcu-child-modal input[type=date]{"
      output << "  width:100%;padding:12px 14px;font-size:17px;box-sizing:border-box;"
      output << "  border:1px solid #ccc;border-radius:4px;margin-top:4px;height:46px;}"
      output << ".pcu-field-block{margin-bottom:20px;}"
      output << ".child-req-field{margin-bottom:16px;}"
      output << ".child-req-field label{font-size:16px;font-weight:bold;color:#333;margin-bottom:6px;display:block;}"
      output << ".child-req-field input,.child-req-field select,.child-req-field textarea{"
      output << "  width:100%;padding:12px 14px;font-size:17px;box-sizing:border-box;"
      output << "  border:1px solid #ccc;border-radius:4px;height:46px;}"
      output << ".child-req-field textarea{height:90px;resize:vertical;}"
      output << "#pcu-status-msg{display:none;margin:12px 0;padding:10px;border-radius:3px;font-size:16px;}"
      output << ".pcu-modal-btns{text-align:center;margin-top:24px;}"
      output << ".pcu-modal-btns button{padding:11px 28px;margin:0 8px;font-size:17px;border-radius:3px;cursor:pointer;border:none;}"
      output << ".pcu-btn-yes{background:#4CAF50;color:#fff;} .pcu-btn-yes:hover{background:#43a047;}"
      output << ".pcu-btn-no{background:#f44336;color:#fff;} .pcu-btn-no:hover{background:#e53935;}"
      output << ".pcu-subtask-btn{display:inline-flex;align-items:center;gap:2px;"
      output << "  background:none;color:#1976D2 !important;border:none;border-radius:0;"
      output << "  padding:0;font-size:0.9em;cursor:pointer;text-decoration:none !important;"
      output << "  margin-right:8px;vertical-align:middle;white-space:nowrap;font-weight:bold;}"
      output << ".pcu-subtask-btn:hover{color:#0d47a1 !important;text-decoration:underline !important;}"
      output << "</style>"

      # ── Modal HTML (always rendered, hidden by default) ────────────────────
      output << "<div id='pcu-child-modal'>"
      output << "  <div class='pcu-modal-box'>"
      output << "    <h3>Create Child Issue</h3>"
      output << "    <p class='pcu-desc'>Create a child issue under <strong>##{issue.id} &ndash; #{safe_subject}</strong>.</p>"

      output << "    <div class='pcu-field-block'>"
      output << "      <label for='pcu-tracker-select'>Child issue type <span style='color:red'>*</span></label>"
      output << "      <select id='pcu-tracker-select' onchange='pcuLoadRequiredFields(#{issue.id})'>"
      trackers.each_with_index do |t, i|
        output << "        <option value='#{t.id}'#{i == 0 ? ' selected' : ''}>#{ERB::Util.html_escape(t.name)}</option>"
      end
      output << "      </select>"
      output << "    </div>"

      output << "    <div class='pcu-field-block'>"
      output << "      <label for='pcu-subject'>Child subject <span style='color:red'>*</span></label>"
      output << "      <input type='text' id='pcu-subject' value='#{safe_subject}' placeholder='Enter child issue subject'>"
      output << "    </div>"

      output << "    <div id='pcu-required-fields'></div>"
      output << "    <div id='pcu-status-msg'></div>"

      output << "    <div class='pcu-modal-btns'>"
      output << "      <button type='button' class='pcu-btn-yes' id='pcu-submit-btn'"
      output << "              onclick='pcuCreateChild(#{issue.id})'>Yes, Create Child</button>"
      output << "      <button type='button' class='pcu-btn-no' onclick='pcuCloseModal()'>No</button>"
      output << "    </div>"
      output << "  </div>"
      output << "</div>"

      # ── JavaScript ────────────────────────────────────────────────────────
      output << "<script type='text/javascript'>"

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
      output << "  var btn=document.getElementById('pcu-submit-btn');"
      output << "  if(btn){btn.disabled=false;btn.textContent='Yes, Create Child';}"
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
      output << "  }).then(function(r){return r.json();})"
      output << "  .then(function(json){"
      output << "    if(!json.fields||json.fields.length===0) return;"
      output << "    var hd=document.createElement('p');"
      output << "    hd.style.cssText='font-weight:bold;margin:14px 0 6px;color:#333;font-size:13px;border-top:1px solid #eee;padding-top:12px;';"
      output << "    hd.textContent='Additional fields for child issue:';"
      output << "    box.appendChild(hd);"
      output << "    json.fields.forEach(function(cf){"
      output << "      var w=document.createElement('div'); w.className='child-req-field';"
      output << "      var lb=document.createElement('label');"
      output << "      var badge=cf.is_standard"
      output << "        ? '<span style=\"font-size:10px;background:#1976D2;color:#fff;border-radius:3px;padding:1px 5px;margin-left:5px;\">standard</span>'"
      output << "        : (cf.is_required"
      output << "          ? '<span style=\"font-size:10px;background:#f44336;color:#fff;border-radius:3px;padding:1px 5px;margin-left:5px;\">required</span>'"
      output << "          : '<span style=\"font-size:10px;background:#888;color:#fff;border-radius:3px;padding:1px 5px;margin-left:5px;\">optional</span>');"
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
      output << "        inp.style.cssText='width:100%;padding:6px;font-size:13px;box-sizing:border-box;';"
      output << "        if(initVal) inp.value=initVal;"
      output << "      } else {"
      output << "        inp=document.createElement('input'); inp.type='text';"
      output << "        if(initVal) inp.value=initVal;"
      output << "      }"
      # Tag inputs with either std_key or cf_id so pcuCreateChild knows how to submit them
      output << "      if(cf.is_standard){ inp.dataset.stdKey=cf.std_key; } else { inp.dataset.cfId=cf.id; }"
      output << "      inp.dataset.required=cf.is_required?'1':'0';"
      output << "      inp.className='pcu-req-cf'; w.appendChild(inp); box.appendChild(w);"
      output << "    });"
      output << "  }).catch(function(){});"
      output << "}"

      # Create child via AJAX
      output << "function pcuCreateChild(parentId){"
      output << "  var tracker=document.getElementById('pcu-tracker-select').value;"
      output << "  var subject=document.getElementById('pcu-subject').value.trim();"
      output << "  if(!tracker){alert('Please select a child issue type.');return;}"
      output << "  if(!subject){alert('Please enter a subject for the child issue.');return;}"
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
      output << "  if(!token){alert('CSRF token not found. Please reload.');return;}"
      output << "  var btn=document.getElementById('pcu-submit-btn');"
      output << "  btn.disabled=true; btn.textContent='Creating...';"
      output << "  var data=new FormData();"
      output << "  data.append('tracker_id',tracker); data.append('subject',subject);"
      output << "  cfInputs.forEach(function(inp){"
      output << "    if(inp.dataset.stdKey&&inp.value){"
      output << "      data.append('std_fields['+inp.dataset.stdKey+']',inp.value);"
      output << "    } else if(inp.dataset.cfId&&inp.value){"
      output << "      data.append('custom_field_values['+inp.dataset.cfId+']',inp.value);"
      output << "    }"
      output << "  });"
      output << "  fetch('/redmine_parent_to_child_update/child_issues/create/'+parentId,{"
      output << "    method:'POST',"
      output << "    headers:{'X-CSRF-Token':token,'X-Requested-With':'XMLHttpRequest','Accept':'application/json'},"
      output << "    body:data, credentials:'same-origin'"
      output << "  }).then(function(r){"
      output << "    return r.text().then(function(t){"
      output << "      if(!r.ok){try{var j=JSON.parse(t);throw new Error(j.error||t);}catch(e){throw new Error(t);}}"
      output << "      return JSON.parse(t);"
      output << "    });"
      output << "  }).then(function(json){"
      output << "    if(json.error){"
      output << "      pcuShowStatus(json.error,'#fdecea','#c62828');"
      output << "      btn.disabled=false; btn.textContent='Yes, Create Child';"
      # Chain: redirect to newly created child's page (popup will auto-open there)
      output << "    } else if(json.redirect_to){"
      output << "      pcuShowStatus('Child created! Loading next step...','#e8f5e9','#2e7d32');"
      output << "      setTimeout(function(){window.location.href=json.redirect_to;},900);"
      # Loop: stay on same page, re-open popup so user can create another sibling
      output << "    } else if(json.loop){"
      output << "      pcuShowStatus('Child created! Create another child or click No when done.','#e8f5e9','#2e7d32');"
      output << "      setTimeout(function(){"
      output << "        document.getElementById('pcu-required-fields').innerHTML='';"
      output << "        document.getElementById('pcu-status-msg').style.display='none';"
      output << "        document.getElementById('pcu-subject').value=#{safe_subject.inspect};"
      output << "        btn.disabled=false; btn.textContent='Yes, Create Child';"
      output << "        pcuLoadRequiredFields(parentId);"
      output << "      },1200);"
      output << "    } else {"
      output << "      pcuShowStatus('Child created!','#e8f5e9','#2e7d32');"
      output << "      setTimeout(function(){window.location.reload();},1200);"
      output << "    }"
      output << "  }).catch(function(err){"
      output << "    pcuShowStatus(err.message,'#fdecea','#c62828');"
      output << "    btn.disabled=false; btn.textContent='Yes, Create Child';"
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
      output << "    pcuLoadRequiredFields(issueId);"
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

      # DOMContentLoaded — move modal to <body> so position:fixed works correctly,
      # then auto-open for CR flow and inject the subtask button
      output << "document.addEventListener('DOMContentLoaded',function(){"
      output << "  var modal=document.getElementById('pcu-child-modal');"
      output << "  if(modal&&modal.parentNode!==document.body) document.body.appendChild(modal);"
      if auto_open
        output << "  modal.style.display='block';"
        output << "  pcuLoadRequiredFields(#{issue.id});"
      end
      output << "  pcuInjectSubtaskButton(#{issue.id});"
      output << "});"

      output << "</script>"
      output.html_safe
    end

  end
end
