module LlmLogs
  module BatchesHelper
    ROUTING_VALUE_LENGTH = 80

    def routing_display_value(value)
      full_value = routing_full_value(value)
      return full_value if full_value.length <= ROUTING_VALUE_LENGTH

      "#{full_value.first(ROUTING_VALUE_LENGTH - 3)}..."
    end

    def routing_full_value(value)
      case value
      when Hash, Array
        JSON.generate(value)
      when nil
        "null"
      else
        value.to_s
      end
    end
  end
end
