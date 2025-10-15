defmodule KeilaWeb.UIHelpers do
  @moduledoc """
  UI helper functions for the refreshed design system.
  Provides reusable components and utilities for consistent styling.
  """

  import Phoenix.HTML
  import Phoenix.HTML.Form
  import Phoenix.HTML.Link
  import KeilaWeb.Gettext

  @doc """
  Checks if UI refresh feature is enabled.
  """
  def ui_refresh_enabled? do
    case System.get_env("UI_REFRESH", "on") do
      "off" -> false
      _ -> true
    end
  end

  @doc """
  Returns CSS classes for UI refresh if enabled, otherwise returns empty string.
  """
  def ui_refresh_class(class \\ "ui-refresh") do
    if ui_refresh_enabled?(), do: class, else: ""
  end
end
