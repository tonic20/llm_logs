require "kramdown"
require "kramdown-parser-gfm"

module LlmLogs
  module FormattingHelper
    MARKDOWN_TAGS = %w[
      a blockquote br code del em h1 h2 h3 h4 h5 h6 hr li ol p pre strong
      table tbody td th thead tr ul
    ].freeze
    MARKDOWN_ATTRIBUTES = %w[href title].freeze

    def format_duration_ms(ms)
      return "—" if ms.nil?

      "#{number_with_delimiter(sprintf('%.0f', ms))} ms"
    end

    def render_markdown(text)
      html = Kramdown::Document.new(
        text.to_s,
        input: "GFM",
        hard_wrap: true,
        syntax_highlighter: nil
      ).to_html

      sanitize html, tags: MARKDOWN_TAGS, attributes: MARKDOWN_ATTRIBUTES
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
