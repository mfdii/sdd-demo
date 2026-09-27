#!/bin/bash
set -e

# Must be run from inside the project directory (where package.json lives)
if [ ! -f "package.json" ] || [ ! -f "src/server.ts" ]; then
  echo "ERROR: rename.sh must be run from inside the project directory."
  echo "  cd <your-project> && bash rename.sh <app-name> '<description>'"
  exit 1
fi

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: cd <your-project> && bash rename.sh <app-name> <app-description>"
  echo "Example: cd mcp-weather && bash rename.sh mcp-weather 'MCP server for weather data'"
  exit 1
fi

APP_NAME="$1"
APP_DESC="$2"
DISPLAY_NAME=$(echo "$APP_NAME" | sed 's/-/ /g' | perl -pe 's/\b(\w)/\U$1/g')

echo "Renaming to: $APP_NAME"
echo "Description: $APP_DESC"
echo "Display name: $DISPLAY_NAME"
echo ""

FILES=$(find . -type f \( -name '*.ts' -o -name '*.js' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' \) \
  -not -path '*/node_modules/*' \
  -not -path '*/dist/*' \
  -not -path '*/.git/*' \
  -not -name 'package-lock.json' \
  -not -name 'rename.sh' \
  -not -name 'validate.sh')

echo "--- Replacing app name ---"
perl -pi -e "s/mcp-hello-world/$APP_NAME/g" $FILES
echo "  Replaced mcp-hello-world -> $APP_NAME"

echo "--- Replacing description ---"
perl -pi -e "s/Hello world MCP v2 server/$APP_DESC/g" $FILES
echo "  Replaced description -> $APP_DESC"

echo "--- Replacing display name ---"
perl -pi -e "s/MCP Hello World/$DISPLAY_NAME/g" $FILES
echo "  Replaced display name -> $DISPLAY_NAME"

echo "--- Replacing git URL ---"
perl -pi -e "s|https://github.com/your-org/mcp-hello-world.git|https://github.com/your-org/$APP_NAME.git|g" $FILES
echo "  Replaced git URL"

REMAINING=$(grep -rl 'mcp-hello-world' --include='*.ts' --include='*.json' --include='*.yaml' --include='*.js' . 2>/dev/null | grep -v node_modules | grep -v '.git/' | grep -v 'dist/' | grep -v 'package-lock.json' || true)
if [ -n "$REMAINING" ]; then
  echo ""
  echo "WARNING: mcp-hello-world still found in:"
  echo "$REMAINING"
  exit 1
fi

rm -rf dist

echo ""
echo "Done. Next steps:"
echo "  1. rm -rf node_modules package-lock.json && npm install"
echo "  2. Edit src/server.ts — rewrite the entire file, replacing the hello tool with your tools"
echo "  3. npm run build"
echo "  4. bash validate.sh"
