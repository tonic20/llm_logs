module LlmLogs
  class Prompt < ApplicationRecord
    has_many :versions, class_name: "LlmLogs::PromptVersion", dependent: :destroy

    validates :slug, presence: true, uniqueness: true
    validates :name, presence: true

    def self.load(slug)
      find_by!(slug: slug)
    end

    def current_version
      versions.order(version_number: :desc).first
    end

    def version(number)
      versions.find_by!(version_number: number)
    end

    def build(variables = {})
      ver = current_version
      raise "No versions exist for prompt '#{slug}'" unless ver

      trace = LlmLogs::Tracer.current_trace
      if trace && trace.prompt_version_id.nil?
        trace.update_column(:prompt_version_id, ver.id)
      end

      ver.render(variables)
    end

    def update_content!(messages:, model: nil, model_params: {}, changelog: nil)
      next_number = (versions.maximum(:version_number) || 0) + 1

      versions.create!(
        version_number: next_number,
        messages: messages,
        model: model,
        model_params: model_params,
        changelog: changelog
      )
    end

    def rollback_to!(version_number)
      source = version(version_number)
      update_content!(
        messages: source.messages,
        model: source.model,
        model_params: source.model_params,
        changelog: "Rollback to version #{version_number}"
      )
    end
  end
end
