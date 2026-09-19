#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
SOURCE=ios/App/App/StockLedger
swiftc -swift-version 5 -O -parse-as-library "$SOURCE/L10n.swift" "$SOURCE/Models.swift" "$SOURCE/Engine.swift" "$SOURCE/CsvImport.swift" "$SOURCE/QuoteService.swift" "$SOURCE/Store.swift" "$SOURCE/HSBCStatement.swift" tests/native/EngineGoldenTests.swift tests/native/SafetyTests.swift tests/native/NativeTests.swift -o build/native-tests
build/native-tests
