module LlmLogs
  class PromptsController < ApplicationController
    SORT_COLUMNS = { "name" => :name, "slug" => :slug, "updated" => :updated_at }.freeze

    def index
      tag = params[:tag].is_a?(String) ? params[:tag].presence : nil
      @sort      = SORT_COLUMNS.key?(params[:sort]) ? params[:sort] : "name"
      @direction = params[:direction] == "desc" ? "desc" : "asc"
      scope = Prompt.order(SORT_COLUMNS.fetch(@sort) => @direction.to_sym).includes(:versions)
      scope = scope.with_tag(tag) if tag
      @prompts    = scope.page(params[:page]).per(LlmLogs.page_size)
      @active_tag = tag
      @all_tags   = Prompt.pluck(:tags).flatten.compact.uniq.sort
    end

    def show
      @prompt = Prompt.find(params[:id])
      @current_version = @prompt.current_version
      @versions = @prompt.versions.order(version_number: :desc).limit(5)
    end

    def new
      @prompt = Prompt.new
    end

    def create
      @prompt = Prompt.new(prompt_params)

      ActiveRecord::Base.transaction do
        @prompt.save!
        @prompt.update_content!(**version_params) if version_params[:messages].present?
      end
      redirect_to prompt_path(@prompt), notice: "Prompt created."
    rescue ActiveRecord::RecordInvalid => e
      surface_version_errors(e)
      render :new, status: :unprocessable_entity
    end

    def edit
      @prompt = Prompt.find(params[:id])
      @current_version = @prompt.current_version
    end

    def update
      @prompt = Prompt.find(params[:id])

      ActiveRecord::Base.transaction do
        @prompt.update!(prompt_params)
        @prompt.update_content!(**version_params) if version_params[:messages].present?
      end
      redirect_to prompt_path(@prompt), notice: "Prompt updated."
    rescue ActiveRecord::RecordInvalid => e
      @current_version = @prompt.current_version
      surface_version_errors(e)
      render :edit, status: :unprocessable_entity
    end

    def destroy
      @prompt = Prompt.find(params[:id])
      @prompt.destroy
      redirect_to prompts_path, notice: "Prompt deleted."
    end

    private

    def prompt_params
      raw = params.require(:prompt).permit(:slug, :name, :description, :tags_input, tags: [])
      if raw[:tags_input].present?
        raw[:tags] = raw[:tags_input].split(",").map(&:strip).reject(&:blank?)
      end
      raw.except(:tags_input)
    end

    def surface_version_errors(error)
      return if error.record == @prompt

      error.record.errors.full_messages.each { |message| @prompt.errors.add(:base, message) }
    end

    def version_params
      raw = params.require(:prompt).permit(:model, :changelog, model_params: {})
      messages = parse_messages
      {
        messages: messages,
        model: raw[:model],
        model_params: coerce_model_params(raw[:model_params]&.to_h || {}),
        changelog: raw[:changelog]
      }.compact_blank
    end

    def coerce_model_params(params_hash)
      params_hash.each_with_object({}) do |(key, value), result|
        next if value.blank?

        result[key] = case value
        when /\A\d+\z/ then value.to_i
        when /\A\d+\.\d+\z/ then value.to_f
        else value
        end
      end
    end

    def parse_messages
      return [] unless params[:prompt][:messages].present?

      params[:prompt][:messages].values.map do |msg|
        { "role" => msg[:role], "content" => msg[:content] }
      end.reject { |m| m["content"].blank? }
    end
  end
end
