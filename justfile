# Clean build artifacts
clean:
    rm -rf DerivedData

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
        build

# Run tests with xcodebuild (matches CI)
test:
    xcodebuild test \
        -project Brewy.xcodeproj \
        -scheme Brewy \
        -destination 'platform=macOS' \
        -enableCodeCoverage YES \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO

# Run SwiftLint
lint:
    swiftlint --strict

# Audit GitHub Actions workflows
audit:
    zizmor .github/workflows/

# Run all checks (lint, test, audit)
check: lint test audit
