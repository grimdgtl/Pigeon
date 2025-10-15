defmodule KeilaWeb.SharedView do
  use KeilaWeb, :view
  import Phoenix.HTML.Form

  def error_tag(form, field, opts \\ []) do
    class = Keyword.get(opts, :class, "invalid-feedback")
    Enum.map(Keyword.get_values(form.errors, field), fn error ->
      content_tag :span, local_translate_error(error), class: class
    end)
  end

  defp local_translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(KeilaWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(KeilaWeb.Gettext, "errors", msg, opts)
    end
  end
end
