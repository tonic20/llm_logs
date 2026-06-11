module LlmLogs
  class Batch
    # Translates a {name:, schema:, strict:} schema (the shape RubyLLM::Chat#with_schema
    # produces) into the OpenAI Responses API `text.format` block. The batch path builds
    # request bodies directly via RubyLLM.batch#add(**extra), bypassing with_schema, so
    # we must hand the json_schema block in ourselves.
    module SchemaFormat
      module_function

      def call(schema)
        return nil if schema.nil?

        schema = schema.symbolize_keys if schema.respond_to?(:symbolize_keys)
        {
          format: {
            type: "json_schema",
            name: schema[:name] || "response",
            schema: schema[:schema] || schema,
            strict: schema.key?(:strict) ? schema[:strict] : true
          }
        }
      end
    end
  end
end
