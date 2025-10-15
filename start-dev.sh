#!/bin/bash

# Start development environment with MailHog
echo "Starting Keila development environment with MailHog..."

# Start the services
docker-compose -f docker-compose.dev.yml up -d

echo ""
echo "🚀 Services started!"
echo ""
echo "📧 MailHog Web UI: http://localhost:8025"
echo "🌐 Keila Application: http://localhost:4000"
echo "🗄️  PostgreSQL: localhost:5432"
echo ""
echo "📋 Default Keila credentials:"
echo "   Email: admin@example.com"
echo "   Password: change_me_in_production"
echo ""
echo "📨 All emails sent by Keila will be captured by MailHog"
echo "   and can be viewed in the web UI at http://localhost:8025"
echo ""
echo "To stop the services, run:"
echo "  docker-compose -f docker-compose.dev.yml down"
echo ""
echo "To view logs, run:"
echo "  docker-compose -f docker-compose.dev.yml logs -f"
