# Keila Development Makefile
# Provides convenient commands for development workflow

.PHONY: help dev dev-start dev-stop dev-clean dev-build dev-test dev-logs dev-shell

# Default target
help:
	@echo "Keila Development Commands"
	@echo "========================"
	@echo ""
	@echo "Development:"
	@echo "  make dev          - Start development server with auto-reload"
	@echo "  make dev-start    - Start development server (alias for dev)"
	@echo "  make dev-stop     - Stop development server"
	@echo "  make dev-clean    - Clean build artifacts and dependencies"
	@echo "  make dev-build    - Build the application"
	@echo "  make dev-test     - Run tests"
	@echo "  make dev-logs     - Show development server logs"
	@echo "  make dev-shell    - Open shell in development container"
	@echo ""
	@echo "Docker:"
	@echo "  make docker-up    - Start development containers"
	@echo "  make docker-down  - Stop development containers"
	@echo "  make docker-logs  - Show container logs"
	@echo ""
	@echo "Database:"
	@echo "  make db-setup     - Setup database (migrate and seed)"
	@echo "  make db-reset     - Reset database (drop, create, migrate, seed)"
	@echo "  make db-migrate   - Run database migrations"
	@echo ""

# Development server commands
dev: dev-start

dev-start:
	@echo "🚀 Starting Keila development server with auto-reload..."
	@./dev/start

dev-stop:
	@echo "🛑 Stopping development server..."
	@docker compose exec pigeon_devcontainer-elixir-1 pkill -f "mix phx.server" 2>/dev/null || true
	@docker compose exec pigeon_devcontainer-elixir-1 pkill -f "beam.smp" 2>/dev/null || true
	@echo "✅ Development server stopped"

dev-clean:
	@echo "🧹 Cleaning build artifacts..."
	@docker compose exec pigeon_devcontainer-elixir-1 bash -c "cd /workspace && mix clean --deps && rm -rf _build deps/assets"
	@echo "✅ Build artifacts cleaned"

dev-build:
	@echo "🔨 Building application..."
	@docker compose exec pigeon_devcontainer-elixir-1 bash -c "cd /workspace && mix deps.get && mix compile --force"
	@echo "✅ Application built"

dev-test:
	@echo "🧪 Running tests..."
	@docker compose exec pigeon_devcontainer-elixir-1 bash -c "cd /workspace && mix test"
	@echo "✅ Tests completed"

dev-logs:
	@echo "📋 Showing development server logs..."
	@docker compose logs -f pigeon_devcontainer-elixir-1

dev-shell:
	@echo "🐚 Opening shell in development container..."
	@docker compose exec pigeon_devcontainer-elixir-1 bash

# Docker commands
docker-up:
	@echo "🐳 Starting development containers..."
	@docker compose -f docker-compose.dev.yml up -d
	@echo "✅ Development containers started"

docker-down:
	@echo "🐳 Stopping development containers..."
	@docker compose -f docker-compose.dev.yml down
	@echo "✅ Development containers stopped"

docker-logs:
	@echo "📋 Showing container logs..."
	@docker compose -f docker-compose.dev.yml logs -f

# Database commands
db-setup:
	@echo "🗄️  Setting up database..."
	@docker compose exec pigeon_devcontainer-elixir-1 bash -c "cd /workspace && mix ecto.migrate && mix run priv/repo/seeds.exs"
	@echo "✅ Database setup complete"

db-reset:
	@echo "🗄️  Resetting database..."
	@docker compose exec pigeon_devcontainer-elixir-1 bash -c "cd /workspace && mix ecto.reset && mix run priv/repo/seeds.exs"
	@echo "✅ Database reset complete"

db-migrate:
	@echo "🗄️  Running database migrations..."
	@docker compose exec pigeon_devcontainer-elixir-1 bash -c "cd /workspace && mix ecto.migrate"
	@echo "✅ Database migrations complete"

# Asset commands
assets-build:
	@echo "🎨 Building assets..."
	@docker compose exec pigeon_devcontainer-elixir-1 bash -c "cd /workspace/assets && npm install && npm run deploy"
	@echo "✅ Assets built"

assets-watch:
	@echo "🎨 Watching assets for changes..."
	@docker compose exec pigeon_devcontainer-elixir-1 bash -c "cd /workspace/assets && npm run watch"
