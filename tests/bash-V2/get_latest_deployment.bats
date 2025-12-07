#!/usr/bin/env bats

setup() {
    # Get the directory of the test file
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    SCRIPT_PATH="$SCRIPT_DIR/../../V2/bash/get_latest_deployment.sh"

    # Create temp directory for test artifacts
    TEST_TEMP_DIR="$(mktemp -d)"
    export GITHUB_OUTPUT="$TEST_TEMP_DIR/github_output.txt"
    touch "$GITHUB_OUTPUT"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# Helper to mock curl responses
mock_curl_success() {
    local deployment_id="$1"
    local json_response="{\"data\":[{\"id\":\"$deployment_id\"}]}"
    echo "${json_response}200"
}

mock_curl_empty() {
    local json_response="{\"data\":[]}"
    echo "${json_response}200"
}

mock_curl_error() {
    local status_code="$1"
    local error_message="$2"
    echo "{\"error\":\"$error_message\"}$status_code"
}

# --- Tests for successful deployment retrieval ---

@test "returns deployment ID for GITHUB vendor" {
    # Create a wrapper script that mocks curl
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"data":[{"id":"12345678-1234-1234-1234-123456789abc"}]}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "Development" \
        "GITHUB"

    [ "$status" -eq 0 ]

    # Check GITHUB_OUTPUT file contains the deployment ID
    grep -q "latestDeploymentId=12345678-1234-1234-1234-123456789abc" "$GITHUB_OUTPUT"
}

@test "outputs deployment ID to stdout" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"data":[{"id":"abcd-1234-efgh-5678"}]}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "Development" \
        "TESTRUN"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Latest CICD Flow Deployment:"* ]]
    [[ "$output" == *"abcd-1234-efgh-5678"* ]]
}

@test "uses custom BaseUrl when provided" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
# Capture the URL being called
echo "$@" >> /tmp/curl_args.txt
echo '{"data":[{"id":"test-id"}]}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "Development" \
        "TESTRUN" \
        "https://custom.api.com"

    [ "$status" -eq 0 ]

    # Verify custom URL was used
    grep -q "custom.api.com" /tmp/curl_args.txt
    rm -f /tmp/curl_args.txt
}

# --- Tests for empty deployment list ---

@test "handles no deployments gracefully for GITHUB" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"data":[]}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "Development" \
        "GITHUB"

    [ "$status" -eq 0 ]
    [[ "$output" == *"No latest CICD Flow Deployments found"* ]]

    # Should write empty deployment ID
    grep -q "latestDeploymentId=" "$GITHUB_OUTPUT"
}

# --- Tests for AZUREDEVOPS vendor ---

@test "outputs Azure DevOps variable format" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"data":[{"id":"azure-deployment-id"}]}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "Development" \
        "AZUREDEVOPS"

    [ "$status" -eq 0 ]
    [[ "$output" == *"##vso[task.setvariable variable=latestDeploymentId;isOutput=true]azure-deployment-id"* ]]
}

# --- Tests for unsupported vendor ---

@test "exits with code 1 for unknown vendor" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"data":[{"id":"some-id"}]}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "Development" \
        "UNKNOWN_VENDOR"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Please use one of the supported Pipeline Vendors"* ]]
}

# --- Tests for API errors ---

@test "exits with code 1 on HTTP 401 error" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"error":"Unauthorized"}401'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "invalid-api-key" \
        "Development" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected API Response Code: 401"* ]]
}

@test "exits with code 1 on HTTP 500 error" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"error":"Internal Server Error"}500'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "Development" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected API Response Code: 500"* ]]
}

@test "outputs error details on API failure" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"error":"Project not found","message":"The specified project does not exist"}404'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "nonexistent-project" \
        "test-api-key" \
        "Development" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected API Response Code: 404"* ]]
    [[ "$output" == *"---Response End---"* ]]
}
