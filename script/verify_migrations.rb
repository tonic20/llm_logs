# Run only against a disposable database; this script rolls back and drops its tables.
ENV['RAILS_ENV'] = 'test'
require_relative '../spec/dummy/config/environment'
require 'stringio'
raise 'Set LLM_LOGS_DISPOSABLE_DATABASE=1 for this destructive test' unless ENV['LLM_LOGS_DISPOSABLE_DATABASE'] == '1'
context = ActiveRecord::MigrationContext.new(File.expand_path('../db/migrate', __dir__))
context.migrate
context.migrate(0)
raise 'Rollback left engine tables' if ActiveRecord::Base.connection.tables.any? { |name| name.start_with?('llm_logs_') }
context.migrate
stream = StringIO.new
ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, stream)
ActiveRecord::Base.connection.disable_referential_integrity do
  ActiveRecord::Base.connection.tables.reverse_each { |name| ActiveRecord::Base.connection.drop_table(name, force: :cascade) }
end
eval(stream.string, TOPLEVEL_BINDING, 'roundtrip-schema.rb')
prompt = LlmLogs::Prompt.create!(slug: 'migration-check', name: 'Migration check', tags: ['test'])
prompt.update_content!(messages: [{ 'role' => 'user', 'content' => 'Hello {{name}}' }])
raise 'JSON/tag round trip failed' unless LlmLogs::Prompt.with_tag('test').first.build(name: 'Ruby')[:messages].first[:content] == 'Hello Ruby'
puts "Install, rollback and schema reload verified: #{ActiveRecord::Base.connection.adapter_name}"
