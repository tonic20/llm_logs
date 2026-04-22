module LlmLogs
  module PromptsHelper
    def sort_link(label, column)
      active = @sort == column
      next_direction = active && @direction == "asc" ? "desc" : "asc"
      arrow = active ? (@direction == "asc" ? " ↑" : " ↓") : ""

      link_to(
        "#{label}#{arrow}",
        prompts_path(
          sort: column,
          direction: next_direction,
          tag: @active_tag
        ),
        class: "hover:text-gray-700 #{'text-gray-900' if active}"
      )
    end
  end
end
