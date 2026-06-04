require "spec_helper"

module LlmLogs
  RSpec.describe FormattingHelper, type: :helper do
    describe "#render_markdown" do
      it "renders standard markdown" do
        html = helper.render_markdown("## Title\n\n**bold** and `code`")

        expect(html).to include("<h2")
        expect(html).to include("<strong>bold</strong>")
        expect(html).to include("<code>code</code>")
      end

      it "shows custom tags (e.g. prompt delimiters) as visible text instead of dropping them" do
        html = helper.render_markdown("Wrap it:\n<user_request>\nhello\n</user_request>")

        expect(html).to include("&lt;user_request&gt;")
        expect(html).to include("&lt;/user_request&gt;")
        # the literal tag must not survive as a real (invisible/stripped) element
        expect(html).not_to include("<user_request>")
      end

      it "shows inline tag mentions in prose without restructuring them" do
        html = helper.render_markdown("Data is wrapped in <transcript>DATA</transcript> tags.")

        expect(html).to include("&lt;transcript&gt;DATA&lt;/transcript&gt;")
      end

      it "does not double-escape an existing ampersand" do
        html = helper.render_markdown("Tom & Jerry")

        expect(html).to include("Tom &amp; Jerry")
        expect(html).not_to include("&amp;amp;")
      end
    end
  end
end
