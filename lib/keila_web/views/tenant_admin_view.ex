defmodule KeilaWeb.TenantAdminView do
  use KeilaWeb, :view
  import Phoenix.HTML.Form
  alias KeilaWeb.Router.Helpers, as: Routes

  def error_tag(form, field) do
    Enum.map(Keyword.get_values(form.errors, field), fn error ->
      content_tag :span, local_translate_error(error), class: "invalid-feedback"
    end)
  end

  defp local_translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate "is invalid" in the "errors" domain
    #     dngettext "errors", "is invalid", "are invalid", count
    #
    # We need to pass the count where applicable.
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
