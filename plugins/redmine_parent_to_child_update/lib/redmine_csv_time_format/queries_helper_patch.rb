# ─────────────────────────────────────────────────────────────────────────────
# CSV Time Format – QueriesHelper patch
#
# Redmine stores estimated/spent/remaining hours as Float (decimal hours).
# When users download a CSV the values come out as e.g. "48.5833333".
# This patch intercepts csv_content for every hours column and formats the
# value as HH:MM (e.g. 48:35) so the exported file is human-readable and
# can be used directly in spreadsheets without manual conversion.
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
    # We intercept hours columns; everything else falls through to Redmine's
    # original implementation via super.
    def csv_content(column, issue)
      col_name = column.name.to_s
      return super unless HOURS_COLUMN_NAMES.include?(col_name)

      value = column.value_object(issue)
      return '' if value.nil?

      if value.is_a?(Float) || value.is_a?(Numeric)
        RedmineCsvTimeFormat.hours_to_hhmm(value.to_f)
      else
        super
      end
    end
  end

  # Convert a decimal-hours Float to "H:MM" string.
  # Examples:
  #   48.5833... => "48:35"
  #   0.5        => "0:30"
  #   0.0        => "0:00"
  def self.hours_to_hhmm(float_hours)
    return '' if float_hours.nil?
    negative   = float_hours < 0
    total_mins = (float_hours.abs * 60).round
    h          = total_mins / 60
    m          = total_mins % 60
    "#{negative ? '-' : ''}#{h}:#{format('%02d', m)}"
  end
end
