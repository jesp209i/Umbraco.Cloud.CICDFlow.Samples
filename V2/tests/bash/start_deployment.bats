#!/usr/bin/env bats

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    SCRIPT_PATH="$SCRIPT_DIR/../../bash/start_deployment.sh"

    TEST_TEMP_DIR="$(mktemp -d)"
    export GITHUB_OUTPUT="$TEST_TEMP_DIR/github_output.txt"
    touch "$GITHUB_OUTPUT"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# --- Tests for successful deployment start ---

@test "starts deployment and returns ID for GITHUB vendor" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"deploymentId":"deploy-12345"}201'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "artifact-123" \
        "Development" \
        "Test deployment" \
        "false" \
        "false" \
        "GITHUB"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Deployment started successfully"* ]]
    [[ "$output" == *"deploy-12345"* ]]
    grep -q "deploymentId=deploy-12345" "$GITHUB_OUTPUT"
}

@test "starts deployment and returns ID for AZUREDEVOPS vendor" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"deploymentId":"azure-deploy-789"}201'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "artifact-123" \
        "Development" \
        "Test deployment" \
        "false" \
        "false" \
        "AZUREDEVOPS"

    [ "$status" -eq 0 ]
    [[ "$output" == *"##vso[task.setvariable variable=deploymentId;isOutput=true]azure-deploy-789"* ]]
}

@test "starts deployment for TESTRUN vendor" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"deploymentId":"test-deploy"}201'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "artifact-123" \
        "Development" \
        "Test deployment" \
        "false" \
        "false" \
        "TESTRUN"

    [ "$status" -eq 0 ]
    [[ "$output" == *"TESTRUN"* ]]
}

# --- Tests for deployment options ---

@test "outputs deployment options in request" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"deploymentId":"test-deploy"}201'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "artifact-456" \
        "Production" \
        "My commit message" \
        "true" \
        "true" \
        "TESTRUN"

    [ "$status" -eq 0 ]
    [[ "$output" == *"targetEnvironmentAlias: Production"* ]]
    [[ "$output" == *"artifactId: artifact-456"* ]]
    [[ "$output" == *"commitMessage: My commit message"* ]]
    [[ "$output" == *"noBuildAndRestore: true"* ]]
    [[ "$output" == *"skipVersionCheck: true"* ]]
}

# --- Tests for custom base URL ---

@test "uses custom BaseUrl when provided" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo "$@" >> /tmp/curl_args.txt
echo '{"deploymentId":"test-deploy"}201'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "artifact-123" \
        "Development" \
        "Test deployment" \
        "false" \
        "false" \
        "TESTRUN" \
        "https://custom.api.com"

    [ "$status" -eq 0 ]
    grep -q "custom.api.com" /tmp/curl_args.txt
    rm -f /tmp/curl_args.txt
}

# --- Tests for default values ---

@test "uses default values for optional parameters" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"deploymentId":"test-deploy"}201'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "artifact-123" \
        "Development" \
        "Test deployment" \
        "" \
        "" \
        "TESTRUN"

    [ "$status" -eq 0 ]
    [[ "$output" == *"noBuildAndRestore: false"* ]]
    [[ "$output" == *"skipVersionCheck: false"* ]]
}

# --- Tests for unsupported vendor ---

@test "exits with error for unknown vendor" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"deploymentId":"test-deploy"}201'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "artifact-123" \
        "Development" \
        "Test deployment" \
        "false" \
        "false" \
        "UNKNOWN"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Please use one of the supported Pipeline Vendors"* ]]
}

# --- Tests for API errors ---

@test "exits with error on HTTP 401" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"error":"Unauthorized"}401'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "invalid-key" \
        "artifact-123" \
        "Development" \
        "Test deployment" \
        "false" \
        "false" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected API Response Code: 401"* ]]
}

@test "exits with error on HTTP 400" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"error":"Bad Request","message":"Invalid artifact ID"}400'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "invalid-artifact" \
        "Development" \
        "Test deployment" \
        "false" \
        "false" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected API Response Code: 400"* ]]
}

@test "exits with error on HTTP 404" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"error":"Project not found"}404'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "nonexistent-project" \
        "test-api-key" \
        "artifact-123" \
        "Development" \
        "Test deployment" \
        "false" \
        "false" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected API Response Code: 404"* ]]
}

@test "outputs error details on API failure" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"error":"Conflict","message":"Deployment already in progress"}409'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "artifact-123" \
        "Development" \
        "Test deployment" \
        "false" \
        "false" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected API Response Code: 409"* ]]
}
