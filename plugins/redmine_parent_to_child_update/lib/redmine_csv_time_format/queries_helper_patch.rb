# ─────────────────────────────────────────────────────────────────────────────
# CSV Time Format – QueriesHelper patch
#
# Redmine stores estimated/spent/remaining hours as Float (decimal hours).
# When users download a CSV the values come out as e.g. "48.5833333" or "0.5".
# This patch intercepts csv_content for every hours column and formats the
# value as HH:MM (e.g. 48:35, 00:30) so the exported file is human-readable.
# ─────────────────────────────────────────────────────────────────────────────
module RedmineCsvTimeFormat
  module QueriesHelperPatch
    # Redmine column names that hold values in decimal hours
    HOURS_COLUMN_NAMES = %w[
      estimated_hours
      total_estimated_hours
      spent_hours
      total_spent_hours
      remaining_hours
    ].freeze

    # Called once per cell during CSV generation.
    # Intercepts hours columns and formats them as HH:MM.
    # Everything else falls through to Redmine's original implementation.
    def csv_content(column, issue)
      col_name = column.name.to_s
      return super unless HOURS_COLUMN_NAMES.include?(col_name)

      value = column.value_object(issue)
      return '' if value.nil?

      if value.is_a?(Numeric)
        RedmineCsvTimeFormat.hours_to_hhmm(value.to_f)
      else
        super
      end
    end
  end

  # Converts a decimal-hours Float to zero-padded "HH:MM" string.
  # Examples:
  #   0.5        => "00:30"
  #   3.25       => "03:15"
  #   48.5833... => "48:35"
  #   0.0        => "00:00"
  def self.hours_to_hhmm(float_hours)
    return '' if float_hours.nil?
    negative   = float_hours < 0
    total_mins = (float_hours.abs * 60).round
    h          = total_mins / 60
    m          = total_mins % 60
    "#{negative ? '-' : ''}#{format('%02d', h)}:#{format('%02d', m)}"
  end
end
