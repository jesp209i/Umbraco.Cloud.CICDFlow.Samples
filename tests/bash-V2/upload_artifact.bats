#!/usr/bin/env bats

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    SCRIPT_PATH="$SCRIPT_DIR/../../V2/bash/upload_artifact.sh"

    TEST_TEMP_DIR="$(mktemp -d)"
    export GITHUB_OUTPUT="$TEST_TEMP_DIR/github_output.txt"
    touch "$GITHUB_OUTPUT"

    # Create a test artifact file
    ARTIFACT_FILE="$TEST_TEMP_DIR/artifact.zip"
    echo "mock artifact content" > "$ARTIFACT_FILE"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# --- Tests for missing file path ---

@test "exits with error when filePath is empty" {
    run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "" \
        "test description" \
        "1.0.0" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"filePath is empty"* ]]
}

@test "exits with error when file does not exist" {
    run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "/nonexistent/file.zip" \
        "test description" \
        "1.0.0" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"filePath does not contain a file"* ]]
}

# --- Tests for successful upload ---

@test "uploads artifact and returns ID for GITHUB vendor" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"artifactId":"artifact-12345"}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "$ARTIFACT_FILE" \
        "Test artifact" \
        "1.0.0" \
        "GITHUB"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Artifact uploaded"* ]]
    [[ "$output" == *"artifact-12345"* ]]
    grep -q "artifactId=artifact-12345" "$GITHUB_OUTPUT"
}

@test "uploads artifact and returns ID for AZUREDEVOPS vendor" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"artifactId":"azure-artifact-789"}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "$ARTIFACT_FILE" \
        "Test artifact" \
        "1.0.0" \
        "AZUREDEVOPS"

    [ "$status" -eq 0 ]
    [[ "$output" == *"##vso[task.setvariable variable=artifactId;isOutput=true]azure-artifact-789"* ]]
}

@test "uploads artifact for TESTRUN vendor" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"artifactId":"test-artifact"}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "$ARTIFACT_FILE" \
        "Test artifact" \
        "1.0.0" \
        "TESTRUN"

    [ "$status" -eq 0 ]
    [[ "$output" == *"TESTRUN"* ]]
}

# --- Tests for custom base URL ---

@test "uses custom BaseUrl when provided" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo "$@" >> /tmp/curl_args.txt
echo '{"artifactId":"test-artifact"}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "$ARTIFACT_FILE" \
        "Test artifact" \
        "1.0.0" \
        "TESTRUN" \
        "https://custom.api.com"

    [ "$status" -eq 0 ]
    grep -q "custom.api.com" /tmp/curl_args.txt
    rm -f /tmp/curl_args.txt
}

# --- Tests for unsupported vendor ---

@test "exits with error for unknown vendor" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"artifactId":"test-artifact"}200'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "$ARTIFACT_FILE" \
        "Test artifact" \
        "1.0.0" \
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
        "$ARTIFACT_FILE" \
        "Test artifact" \
        "1.0.0" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected API Response Code: 401"* ]]
}

@test "exits with error on HTTP 500" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"error":"Internal Server Error"}500'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "$ARTIFACT_FILE" \
        "Test artifact" \
        "1.0.0" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected API Response Code: 500"* ]]
}

@test "outputs error details on API failure" {
    cat > "$TEST_TEMP_DIR/curl" << 'EOF'
#!/bin/bash
echo '{"error":"Bad Request","message":"Invalid file format"}400'
EOF
    chmod +x "$TEST_TEMP_DIR/curl"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "test-project" \
        "test-api-key" \
        "$ARTIFACT_FILE" \
        "Test artifact" \
        "1.0.0" \
        "GITHUB"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unexpected API Response Code: 400"* ]]
    [[ "$output" == *"---Response End---"* ]]
}
