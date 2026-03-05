module LlmLogs
  module FormattingHelper
    def format_duration_ms(ms)
      return "—" if ms.nil?

      "#{number_with_delimiter(sprintf('%.0f', ms))} ms"
    end
  end
end
