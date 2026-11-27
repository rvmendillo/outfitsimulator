#!/usr/bin/env bash
# One-time local setup on a Mac: converts the clothing parser and generates
# the Xcode project. Requires Python 3.12 and XcodeGen (brew install xcodegen).
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -d Models/build/ClothingParserModel.mlpackage ]]; then
  python3 -m venv Models/.venv
  Models/.venv/bin/pip install --upgrade pip
  Models/.venv/bin/pip install -r Models/requirements.txt
  Models/.venv/bin/python Models/convert_clothing_parser.py --output Models/build/ClothingParserModel.mlpackage
fi
xcodegen generate
echo "Open OutfitSimulator.xcodeproj in Xcode."
