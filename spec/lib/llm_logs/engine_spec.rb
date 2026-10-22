require "spec_helper"
require "rake"

RSpec.describe LlmLogs::Engine do
  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new

    example.run
  ensure
    Rake.application = original_application
  end

  it "defines each rake task once when the host app loads its tasks" do
    Rails.application.load_tasks

    expect(Rake::Task["llm_logs:prompts:sync"].actions.size).to eq(1)
  end
end
