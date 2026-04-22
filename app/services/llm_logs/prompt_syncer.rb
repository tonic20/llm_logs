require "yaml"
require "pathname"

module LlmLogs
  class PromptSyncer
    REQUIRED_FIELDS = %w[slug name].freeze

    def self.sync_all(root:, subfolders:)
      root = Pathname.new(root)
      subfolders.each do |sub|
        dir = root / sub
        next unless dir.directory?

        Dir.glob(dir / "*.md").sort.each do |path|
          # Skip files that are referenced as body_file targets rather than
          # top-level prompts — those have no top-level `slug:` and are pulled
          # in by the parent template instead.
          pathname = Pathname.new(path)
          next if body_file_only?(pathname)
          new(path: pathname, auto_tag: sub).call
        end
      end
    end

    def self.body_file_only?(path)
      raw = File.read(path)
      # Files referenced as body_file targets have no YAML front-matter.
      # Files with front-matter are prompts and will be validated (missing
      # slug/name raises a clear error rather than being silently skipped).
      !raw.start_with?("---")
    end

    def self.parse(raw)
      _, front_yaml, body = raw.split(/^---\s*$/, 3)
      [YAML.safe_load(front_yaml.to_s, permitted_classes: [Symbol], aliases: true) || {}, body.to_s.sub(/\A\n+/, "")]
    end

    def initialize(path:, auto_tag:)
      @path     = Pathname.new(path)
      @auto_tag = auto_tag
    end

    def call
      raw = @path.read
      raise "Missing front-matter in #{@path}" unless raw.start_with?("---")

      front, body = self.class.parse(raw)
      REQUIRED_FIELDS.each do |field|
        raise "Missing required front-matter field '#{field}' in #{@path}" unless front[field].is_a?(String) && !front[field].strip.empty?
      end

      ActiveRecord::Base.transaction do
        tags = (Array(front["tags"]) + [@auto_tag]).map(&:to_s).uniq
        prompt = LlmLogs::Prompt.find_or_initialize_by(slug: front["slug"])
        created = prompt.new_record?

        prompt.name        = front["name"]
        prompt.description = front["description"]
        prompt.tags        = tags
        prompt.save!

        messages = build_messages(front, body)
        model    = front["model"]
        model_params = front["model_params"].is_a?(Hash) ? front["model_params"] : {}
        model_params = model_params.deep_stringify_keys

        if version_needs_update?(prompt, messages, model, model_params)
          prompt.update_content!(messages: messages, model: model, model_params: model_params, changelog: "Synced from #{@path.basename}")
          status = created ? "Created" : "Updated"
        else
          status = "Unchanged"
        end

        log "#{status}: #{prompt.slug}"
      end
    end

    private

    def build_messages(front, body)
      if front["messages"].is_a?(Array)
        front["messages"].map do |msg|
          msg = msg.deep_stringify_keys if msg.is_a?(Hash)
          content =
            if msg["body_file"]
              body_path = @path.parent / msg["body_file"]
              raise "Missing body_file #{msg['body_file']} referenced by #{@path}" unless body_path.exist?
              body_path.read
            else
              msg["content"].to_s
            end
          { "role" => msg["role"].to_s, "content" => content }
        end
      else
        [{ "role" => "system", "content" => body }]
      end
    end

    def version_needs_update?(prompt, messages, model, model_params)
      current = prompt.current_version
      return true unless current

      current.messages != messages ||
        current.model.to_s != model.to_s ||
        (current.model_params || {}).deep_stringify_keys != (model_params || {}).deep_stringify_keys
    end

    def log(message)
      if defined?(Rails) && Rails.logger
        Rails.logger.info(message)
      else
        puts message
      end
    end
  end
end
