# Build

# Build the app with xcodebuild
build:
    xcodebuild \
        -project Brewy.xcodeproj \
        -scheme Brewy \
        -destination 'generic/platform=macOS' \
        -configuration Debug \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        EXCLUDED_ARCHS=x86_64 \
        build

# Clean build artifacts
clean:
    xcodebuild clean \
        -project Brewy.xcodeproj \
        -scheme Brewy

# Test

# Run unit tests (skips UI tests that require code signing locally)
test:
    xcodebuild test \
        -project Brewy.xcodeproj \
        -scheme Brewy \
        -destination 'platform=macOS' \
        -only-testing:BrewyTests \
        -enableCodeCoverage YES \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        EXCLUDED_ARCHS=x86_64

# Lint

# Audit GitHub Actions workflows
audit:
    zizmor .github/workflows/

# Run SwiftLint
lint:
    swiftlint --strict

# Check for typos
typos:
    typos

# Check

# Run all checks
check:
    #!/usr/bin/env bash
    set -euo pipefail
    failed=0
    skipped=()
    run() {
        echo "--- $1 ---"
        if ! "$@"; then
            failed=1
        fi
    }
    skip() {
        echo "--- $1 --- skipped ($2 not found)"
        skipped+=("$2 (brew install $3)")
    }
    if command -v swiftlint &>/dev/null; then
        run swiftlint --strict
    else
        skip lint swiftlint swiftlint
    fi
    if command -v typos &>/dev/null; then
        run typos
    else
        skip typos typos typos-cli
    fi
    if command -v zizmor &>/dev/null; then
        run zizmor .github/workflows/
    else
        skip audit zizmor zizmor
    fi
    run xcodebuild test \
        -project Brewy.xcodeproj \
        -scheme Brewy \
        -destination 'platform=macOS' \
        -only-testing:BrewyTests \
        -enableCodeCoverage YES \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        EXCLUDED_ARCHS=x86_64
    if [ ${#skipped[@]} -gt 0 ]; then
        echo ""
        echo "Checks skipped due to missing tools:"
        for tool in "${skipped[@]}"; do
            echo "  - $tool"
        done
        failed=1
    fi
    exit $failed
