module LlmLogs
  module FormattingHelper
    def format_duration_ms(ms)
      return "—" if ms.nil?

      "#{number_with_delimiter(sprintf('%.0f', ms))} ms"
    end

    def pretty_json(data)
      JSON.pretty_generate(deep_parse_json(data))
    rescue
      data.to_s
    end

    private

    def deep_parse_json(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_parse_json(v) }
      when Array
        obj.map { |v| deep_parse_json(v) }
      when String
        begin
          deep_parse_json(JSON.parse(obj))
        rescue JSON::ParserError
          obj
        end
      else
        obj
      end
    end
  end
end
