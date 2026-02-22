#!/bin/bash
set -e

APP_NAME="MacCleaner"
BUNDLE_DIR="/Applications/${APP_NAME}.app"

if [ -d "${BUNDLE_DIR}" ]; then
    echo "Removing ${BUNDLE_DIR}..."
    rm -rf "${BUNDLE_DIR}"
    echo "${APP_NAME} has been uninstalled."
else
    echo "${APP_NAME} is not installed in /Applications."
fi
