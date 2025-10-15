defmodule Mix.Tasks.Dev.Start do
  @moduledoc """
  Starts the Keila development server with auto-reload enabled.

  This task performs a clean build and starts Phoenix with live reload
  for optimal development experience.

  ## Examples

      mix dev.start

  """
  use Mix.Task

  @shortdoc "Starts Keila dev server with auto-reload"

  def run(_args) do
    Mix.Task.run("compile", ["--force"])
    
    IO.puts("""
    🚀 Starting Keila development server...
    
    ✅ Code recompiled successfully
    🔄 Auto-reload enabled for:
       • Elixir code changes (lib/**/*.ex)
       • Template changes (lib/**/*.heex, lib/**/*.eex)
       • Asset changes (assets/**/*.js, assets/**/*.css, assets/**/*.scss)
       • Static file changes (priv/static/**)
    
    🌐 Server will be available at: http://localhost:4001
    📝 Watch this terminal for live reload messages
    """)
    
    # Start Phoenix server
    Mix.Task.run("phx.server")
  end
end
