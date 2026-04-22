module LlmLogs
  class PromptsController < ApplicationController
    def index
      scope = Prompt.order(:name).includes(:versions)
      scope = scope.with_tag(params[:tag]) if params[:tag].present?
      @prompts    = scope.page(params[:page]).per(25)
      @active_tag = params[:tag].presence
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

      if @prompt.save
        if version_params[:messages].present?
          @prompt.update_content!(**version_params)
        end
        redirect_to prompt_path(@prompt), notice: "Prompt created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @prompt = Prompt.find(params[:id])
      @current_version = @prompt.current_version
    end

    def update
      @prompt = Prompt.find(params[:id])

      if @prompt.update(prompt_params)
        if version_params[:messages].present?
          @prompt.update_content!(**version_params)
        end
        redirect_to prompt_path(@prompt), notice: "Prompt updated."
      else
        render :edit, status: :unprocessable_entity
      end
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
