# Tracker Fields Configuration - shared settings helper
#
# Thin wrapper around Setting.plugin_tracker_fields_configuration so the
# hook (and settings views) don't have to know about the storage shape.
#
# Every read goes through `settings`, which deep-normalizes whatever comes
# back from Setting into plain Hash/Array/String values. This matters
# because Redmine's plugin settings save path can end up storing (or the
# framework can hand back) ActionController::Parameters objects for nested
# form data instead of plain Hashes - those look like Hashes but don't
# support methods like #transform_keys, so calling them directly caused a
# 500 error after saving. Every subsequent lookup then uses hash_at/array_at,
# which never raises even if a saved value's shape doesn't match what's
# expected (e.g. after a manual edit of the settings, or a future format
# change) - it just falls back to an empty Hash/Array.
module TrackerFieldsConfiguration
  # Standard Redmine issue-form fields that a custom field can be inserted
  # after. `core_key` matches the string returned by Tracker#core_fields,
  # so the settings page can filter this list per tracker. status_id and
  # priority_id are always present on every tracker's form, same as the
  # popup field logic in the parent_to_child_update plugin.
  STANDARD_FIELDS = [
    { key: 'status_id',        core_key: 'status_id',        label_key: :field_status         },
    { key: 'priority_id',      core_key: 'priority_id',      label_key: :field_priority        },
    { key: 'assigned_to_id',   core_key: 'assigned_to_id',   label_key: :field_assigned_to      },
    { key: 'category_id',      core_key: 'category_id',      label_key: :field_category         },
    { key: 'fixed_version_id', core_key: 'fixed_version_id', label_key: :field_fixed_version    },
    { key: 'parent_issue_id',  core_key: 'parent_issue_id',  label_key: :field_parent_issue      },
    { key: 'start_date',       core_key: 'start_date',       label_key: :field_start_date       },
    { key: 'due_date',         core_key: 'due_date',         label_key: :field_due_date         },
    { key: 'estimated_hours',  core_key: 'estimated_hours',  label_key: :field_estimated_hours  },
    { key: 'done_ratio',       core_key: 'done_ratio',       label_key: :field_done_ratio       }
  ].freeze

  ALWAYS_PRESENT_CORE_KEYS = %w[status_id priority_id].freeze

  # Recursively converts ActionController::Parameters / Hash / Array into
  # plain Ruby structures with string keys, leaving anything else untouched.
  def self.deep_stringify(value)
    if value.respond_to?(:to_unsafe_h)
      deep_stringify(value.to_unsafe_h)
    elsif value.is_a?(Hash)
      value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
    elsif value.is_a?(Array)
      value.map { |v| deep_stringify(v) }
    else
      value
    end
  end

  def self.settings
    deep_stringify(Setting.plugin_tracker_fields_configuration || {})
  end

  def self.enabled?
    settings['enabled'] != '0'
  end

  # Safely walks a chain of Hash keys (each converted to a String), never
  # raising even if an intermediate value isn't actually a Hash. Returns {}
  # when the path doesn't resolve to a Hash.
  def self.hash_at(*keys)
    current = settings
    keys.each do |key|
      return {} unless current.is_a?(Hash)
      current = current[key.to_s]
    end
    current.is_a?(Hash) ? current : {}
  end

  # Same as hash_at, but for a path that should resolve to an Array.
  def self.array_at(*keys)
    current = settings
    keys.each do |key|
      return [] unless current.is_a?(Hash)
      current = current[key.to_s]
    end
    current.is_a?(Array) ? current : Array(current)
  end

  # Standard fields applicable to a given tracker (status/priority always
  # included, the rest filtered by Tracker#core_fields when available).
  def self.standard_fields_for_tracker(tracker)
    core = tracker.respond_to?(:core_fields) ? Array(tracker.core_fields).map(&:to_s) : []
    STANDARD_FIELDS.select do |f|
      ALWAYS_PRESENT_CORE_KEYS.include?(f[:core_key]) || core.include?(f[:core_key])
    end
  end

  # Custom field ids (as strings) promoted for this project + tracker,
  # in the order they were configured.
  def self.selected_field_ids(project_id, tracker_id)
    array_at('project_tracker_fields', project_id, tracker_id).map(&:to_s).uniq
  end

  # Standard field key a given custom field should be inserted after,
  # for this project + tracker. nil if not configured.
  def self.after_field_key(project_id, tracker_id, custom_field_id)
    hash_at('project_tracker_after', project_id, tracker_id)[custom_field_id.to_s].presence
  end

  # All configured "after" choices for this project + tracker, as a plain
  # Hash of custom_field_id (String) => standard_field_key (String).
  def self.after_fields_for(project_id, tracker_id)
    hash_at('project_tracker_after', project_id, tracker_id)
  end

  # Ordered list of { custom_field_id:, after_field: } for this project +
  # tracker. Skips fields that were checked but never given a target
  # standard field.
  def self.rules_for(project_id, tracker_id)
    return [] unless enabled?

    selected_field_ids(project_id, tracker_id).map do |cf_id|
      after = after_field_key(project_id, tracker_id, cf_id)
      next nil unless after

      { custom_field_id: cf_id, after_field: after }
    end.compact
  end

  # Rules for every tracker configured under this project, as a Hash of
  # tracker_id (String) => rules array (same shape as rules_for). Trackers
  # with no active rules are omitted. Used to embed one project's whole
  # configuration up front, since the issue form's tracker/project switcher
  # reloads client-side without triggering another server-side hook call.
  def self.rules_by_tracker(project_id)
    return {} unless enabled?

    tracker_ids = hash_at('project_tracker_fields', project_id).keys
    tracker_ids.each_with_object({}) do |tracker_id, acc|
      rules = rules_for(project_id, tracker_id)
      acc[tracker_id] = rules unless rules.empty?
    end
  end

  # ═══════════════════════════════════════════════════════════════════════
  # Hide / unhide fields - a separate feature from field promotion above.
  # Stored under its own settings key so it can't interact with or corrupt
  # the promotion config. Hidden field keys are prefixed to tell standard
  # and custom fields apart in one flat list: "cf_<id>" or "std_<key>"
  # (the latter matching STANDARD_FIELDS' :key values), same convention
  # already used elsewhere in this codebase (redmine_parent_to_child_update).
  # ═══════════════════════════════════════════════════════════════════════

  # Raw hidden field keys (each "cf_<id>" or "std_<key>") for a project +
  # tracker, in configured order.
  def self.hidden_field_keys(project_id, tracker_id)
    array_at('project_tracker_hidden_fields', project_id, tracker_id).map(&:to_s).uniq
  end

  def self.hidden_custom_field_ids(project_id, tracker_id)
    hidden_field_keys(project_id, tracker_id)
      .select { |k| k.start_with?('cf_') }
      .map { |k| k.sub(/\Acf_/, '') }
  end

  def self.hidden_standard_field_keys(project_id, tracker_id)
    hidden_field_keys(project_id, tracker_id)
      .select { |k| k.start_with?('std_') }
      .map { |k| k.sub(/\Astd_/, '') }
  end

  # Hidden field keys for every tracker configured under this project, as a
  # Hash of tracker_id (String) => Array of prefixed field keys. Trackers
  # with nothing hidden are omitted.
  def self.hidden_keys_by_tracker(project_id)
    return {} unless enabled?

    tracker_ids = hash_at('project_tracker_hidden_fields', project_id).keys
    tracker_ids.each_with_object({}) do |tracker_id, acc|
      keys = hidden_field_keys(project_id, tracker_id)
      acc[tracker_id] = keys unless keys.empty?
    end
  end
end
