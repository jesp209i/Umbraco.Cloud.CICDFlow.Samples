#!/usr/bin/env bats

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    SCRIPT_PATH="$SCRIPT_DIR/../../bash/get_deployment_status.sh"

    TEST_TEMP_DIR="$(mktemp -d)"

    # Create mock sleep to speed up tests
    cat > "$TEST_TEMP_DIR/sleep" << 'EOF'
#!/bin/bash
# No-op sleep for testing
exit 0
EOF
    chmod +x "$TEST_TEMP_DIR/sleep"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# --- Tests for successful deployment ---

@test "exits successfully when deployment completes" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"deploymentState":"Completed","modifiedUtc":"2024-01-01T00:00:00Z","deploymentStatusMessages":[]}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "deployment-123"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Deployment completed successfully"* ]]
}

@test "outputs deployment status messages" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"deploymentState":"Completed","modifiedUtc":"2024-01-01T00:00:00Z","deploymentStatusMessages":[{"timestampUtc":"2024-01-01T00:00:00Z","message":"Build started"}]}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "deployment-123"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Build started"* ]]
}

# --- Tests for failed deployment ---

@test "exits with error when deployment fails" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"deploymentState":"Failed","modifiedUtc":"2024-01-01T00:00:00Z","deploymentStatusMessages":[]}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "deployment-123"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Deployment failed"* ]]
}

# --- Tests for polling behavior ---

@test "polls until deployment completes" {
    # Create a counter file to track calls
    echo "0" > "$TEST_TEMP_DIR/call_count"

    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
count=$(cat /tmp/bats_call_count 2>/dev/null || echo "0")
count=$((count + 1))
echo "$count" > /tmp/bats_call_count

if [[ $count -lt 3 ]]; then
    echo '{"deploymentState":"InProgress","modifiedUtc":"2024-01-01T00:00:00Z","deploymentStatusMessages":[]}200'
else
    echo '{"deploymentState":"Completed","modifiedUtc":"2024-01-01T00:00:00Z","deploymentStatusMessages":[]}200'
fi
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "deployment-123"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Deployment completed successfully"* ]]

    rm -f /tmp/bats_call_count
}

# --- Tests for custom timeout ---

@test "uses custom timeout when provided" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"deploymentState":"Completed","modifiedUtc":"2024-01-01T00:00:00Z","deploymentStatusMessages":[]}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "deployment-123" \
        "60"

    [ "$status" -eq 0 ]
}

# --- Tests for custom base URL ---

@test "uses custom BaseUrl when provided" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo "$@" >> /tmp/curl_args.txt
echo '{"deploymentState":"Completed","modifiedUtc":"2024-01-01T00:00:00Z","deploymentStatusMessages":[]}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "deployment-123" \
        "1200" \
        "https://custom.api.com"

    [ "$status" -eq 0 ]
    grep -q "custom.api.com" /tmp/curl_args.txt
    rm -f /tmp/curl_args.txt
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
        "deployment-123"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected API Response Code: 401"* ]]
}

@test "exits with error on HTTP 404" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"error":"Deployment not found"}404'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "nonexistent-deployment"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected API Response Code: 404"* ]]
}

# --- Tests for unexpected status ---

@test "exits with error on unexpected deployment status" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"deploymentState":"Unknown","modifiedUtc":"2024-01-01T00:00:00Z","deploymentStatusMessages":[]}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "deployment-123"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected status"* ]]
}
