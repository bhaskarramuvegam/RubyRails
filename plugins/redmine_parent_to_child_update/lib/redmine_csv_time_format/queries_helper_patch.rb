# CSV Time Format: exports decimal-hour columns as HH:MM (e.g. 0.5 => 00:30).
module RedmineCsvTimeFormat
  HOURS_COLUMN_NAMES = %w[
    estimated_hours
    total_estimated_hours
    spent_hours
    total_spent_hours
    remaining_hours
    hours
  ].freeze

  def self.hours_to_hhmm(float_hours)
    return '' if float_hours.nil?
    negative   = float_hours < 0
    total_mins = (float_hours.abs * 60).round
    "#{negative ? '-' : ''}#{format('%02d', total_mins / 60)}:#{format('%02d', total_mins % 60)}"
  end

  # Excel auto-converts a bare "96:00" to a time and shows 96:00:00.
  # ="96:00" forces it to stay text, so Excel displays exactly HH:MM.
  def self.csv_hhmm(float_hours)
    text = hours_to_hhmm(float_hours)
    text.empty? ? text : "=\"#{text}\""
  end

  def self.hours_column?(column)
    column.respond_to?(:name) && HOURS_COLUMN_NAMES.include?(column.name.to_s)
  end

  module QueriesHelperPatch
    # Redmine 4.1+/5/6: csv_content -> csv_value(column, object, value)
    def csv_value(column, object, value)
      if RedmineCsvTimeFormat.hours_column?(column) && value.is_a?(Numeric)
        RedmineCsvTimeFormat.csv_hhmm(value.to_f)
      else
        super
      end
    end

    # Older Redmine: csv_content(column, issue) formats directly
    def csv_content(column, issue)
      if RedmineCsvTimeFormat.hours_column?(column)
        value = column.value_object(issue)
        return RedmineCsvTimeFormat.csv_hhmm(value.to_f) if value.is_a?(Numeric)
      end
      super
    end
  end

  # prepend onto QueriesHelper AND every class/module that already included it
  # (on Ruby < 3.0 a later prepend does not propagate to existing includers).
  def self.apply!
    return unless defined?(::QueriesHelper)
    targets = [::QueriesHelper]
    ObjectSpace.each_object(Module) do |m|
      targets << m if m != ::QueriesHelper && m.include?(::QueriesHelper)
    end
    targets.uniq.each do |t|
      t.send(:prepend, QueriesHelperPatch) unless t.ancestors.include?(QueriesHelperPatch)
    end
  end
end
