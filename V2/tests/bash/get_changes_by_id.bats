#!/usr/bin/env bats

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    SCRIPT_PATH="$SCRIPT_DIR/../../bash/get_changes_by_id.sh"

    TEST_TEMP_DIR="$(mktemp -d)"
    export GITHUB_OUTPUT="$TEST_TEMP_DIR/github_output.txt"
    touch "$GITHUB_OUTPUT"

    DOWNLOAD_FOLDER="$TEST_TEMP_DIR/download"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# --- Tests for missing deployment ID ---

@test "exits with error when deploymentId is missing" {
    run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "" \
        "Development" \
        "$DOWNLOAD_FOLDER" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"I need a DeploymentId"* ]]
}

# --- Tests for no changes (204 response) ---

@test "reports no changes on HTTP 204 for GITHUB" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
# Write empty file and return 204
touch "$6"
echo "204"
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "deployment-123" \
        "Development" \
        "$DOWNLOAD_FOLDER" \
        "GITHUB"

    [ "$status" -eq 0 ]
    [[ "$output" == *"No Changes"* ]]
    grep -q "remoteChanges=no" "$GITHUB_OUTPUT"
}

# --- Tests for changes detected (200 response with content) ---

@test "reports changes detected on HTTP 200 with content for GITHUB" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
# Write patch content to file and return 200
mkdir -p "$(dirname "$6")"
echo "diff --git a/file.txt b/file.txt" > "$6"
echo "200"
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "deployment-123" \
        "Development" \
        "$DOWNLOAD_FOLDER" \
        "GITHUB"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Changes detected"* ]]
    grep -q "remoteChanges=yes" "$GITHUB_OUTPUT"
}

# --- Tests for empty patch file (treated as no changes) ---

@test "reports no changes when patch file is empty" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
# Write empty file and return 200
mkdir -p "$(dirname "$6")"
touch "$6"
echo "200"
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "deployment-123" \
        "Development" \
        "$DOWNLOAD_FOLDER" \
        "GITHUB"

    [ "$status" -eq 0 ]
    [[ "$output" == *"No Changes"* ]]
    grep -q "remoteChanges=no" "$GITHUB_OUTPUT"
}

# --- Tests for AZUREDEVOPS vendor ---

@test "outputs Azure DevOps variable format when changes detected" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
mkdir -p "$(dirname "$6")"
echo "patch content" > "$6"
echo "200"
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "deployment-123" \
        "Development" \
        "$DOWNLOAD_FOLDER" \
        "AZUREDEVOPS"

    [ "$status" -eq 0 ]
    [[ "$output" == *"##vso[task.setvariable variable=remoteChanges;isOutput=true]yes"* ]]
}

# --- Tests for custom base URL ---

@test "uses custom BaseUrl when provided" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo "$@" >> /tmp/curl_args.txt
mkdir -p "$(dirname "$6")"
touch "$6"
echo "204"
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "deployment-123" \
        "Development" \
        "$DOWNLOAD_FOLDER" \
        "TESTRUN" \
        "https://custom.api.com"

    [ "$status" -eq 0 ]
    grep -q "custom.api.com" /tmp/curl_args.txt
    rm -f /tmp/curl_args.txt
}

# --- Tests for API errors ---

@test "exits with error on HTTP 401" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
mkdir -p "$(dirname "$6")"
echo '{"error":"Unauthorized"}' > "$6"
echo "401"
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "invalid-key" \
        "deployment-123" \
        "Development" \
        "$DOWNLOAD_FOLDER" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected API Response Code: 401"* ]]
}

@test "exits with error on HTTP 404" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
mkdir -p "$(dirname "$6")"
echo '{"error":"Not found"}' > "$6"
echo "404"
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "nonexistent-deployment" \
        "Development" \
        "$DOWNLOAD_FOLDER" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected API Response Code: 404"* ]]
}

# --- Tests for unsupported vendor ---

@test "exits with error for unknown vendor" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
mkdir -p "$(dirname "$6")"
touch "$6"
echo "204"
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "deployment-123" \
        "Development" \
        "$DOWNLOAD_FOLDER" \
        "UNKNOWN"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Please use one of the supported Pipeline Vendors"* ]]
}
