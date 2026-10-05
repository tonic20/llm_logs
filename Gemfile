source "https://rubygems.org"

gemspec

# The Bedrock fixes llm_logs used to patch in (crmne/ruby_llm#1024, #1025 and ab4a4f06)
# are on ruby_llm main but in no release yet.
gem "ruby_llm", github: "crmne/ruby_llm", ref: "16ad59b0b5bd6ba26ac38071e08f00aa1771f52b"

gem "pg", "~> 1.5"
gem "sqlite3", ">= 2.1"
gem "puma"

group :development, :test do
  gem "rspec-rails", "~> 7.0"
  gem "factory_bot_rails", "~> 6.4"
  gem "debug"
end
