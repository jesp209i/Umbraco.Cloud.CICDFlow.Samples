#!/usr/bin/env bats

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    SCRIPT_PATH="$SCRIPT_DIR/../../bash/apply_patch.sh"

    TEST_TEMP_DIR="$(mktemp -d)"
    export GITHUB_OUTPUT="$TEST_TEMP_DIR/github_output.txt"
    touch "$GITHUB_OUTPUT"

    # Create a mock patch file
    PATCH_FILE="$TEST_TEMP_DIR/test.patch"
    echo "mock patch content" > "$PATCH_FILE"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# --- Tests for patch already applied ---

@test "exits successfully when patch is already applied" {
    cat > "$TEST_TEMP_DIR/git" << 'EOF'
#!/bin/bash
if [[ "$1" == "config" ]]; then
    exit 0
elif [[ "$1" == "apply" && "$3" == "--reverse" ]]; then
    # Patch already applied (reverse check succeeds)
    exit 0
fi
exit 0
EOF
    chmod +x "$TEST_TEMP_DIR/git"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "$PATCH_FILE" \
        "deployment-123" \
        "TESTRUN" \
        "test-user" \
        "test@example.com"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Patch already applied"* ]]
}

# --- Tests for successful patch application ---

@test "applies patch and outputs SHA for GITHUB vendor" {
    cat > "$TEST_TEMP_DIR/git" << 'EOF'
#!/bin/bash
if [[ "$1" == "config" ]]; then
    exit 0
elif [[ "$1" == "apply" && "$3" == "--reverse" ]]; then
    # Patch not yet applied (reverse check fails)
    exit 1
elif [[ "$1" == "apply" && "$3" == "--check" ]]; then
    # Patch can be applied
    exit 0
elif [[ "$1" == "apply" ]]; then
    # Apply the patch
    exit 0
elif [[ "$1" == "add" ]]; then
    exit 0
elif [[ "$1" == "commit" ]]; then
    exit 0
elif [[ "$1" == "push" ]]; then
    exit 0
elif [[ "$1" == "rev-parse" ]]; then
    echo "abc123def456"
    exit 0
fi
exit 0
EOF
    chmod +x "$TEST_TEMP_DIR/git"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "$PATCH_FILE" \
        "deployment-123" \
        "GITHUB" \
        "test-user" \
        "test@example.com"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Changes are applied successfully"* ]]
    grep -q "updatedSha=abc123def456" "$GITHUB_OUTPUT"
}

@test "applies patch and outputs SHA for AZUREDEVOPS vendor" {
    cat > "$TEST_TEMP_DIR/git" << 'EOF'
#!/bin/bash
if [[ "$1" == "config" ]]; then
    exit 0
elif [[ "$1" == "checkout" ]]; then
    exit 0
elif [[ "$1" == "apply" && "$3" == "--reverse" ]]; then
    exit 1
elif [[ "$1" == "apply" && "$3" == "--check" ]]; then
    exit 0
elif [[ "$1" == "apply" ]]; then
    exit 0
elif [[ "$1" == "add" ]]; then
    exit 0
elif [[ "$1" == "commit" ]]; then
    exit 0
elif [[ "$1" == "push" ]]; then
    exit 0
elif [[ "$1" == "rev-parse" ]]; then
    echo "azuresha789"
    exit 0
fi
exit 0
EOF
    chmod +x "$TEST_TEMP_DIR/git"

    export BUILD_SOURCEBRANCHNAME="main"
    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "$PATCH_FILE" \
        "deployment-123" \
        "AZUREDEVOPS" \
        "test-user" \
        "test@example.com"

    [ "$status" -eq 0 ]
    [[ "$output" == *"##vso[task.setvariable variable=updatedSha;isOutput=true]azuresha789"* ]]
}

# --- Tests for patch application failure ---

@test "exits with error when patch cannot be applied" {
    cat > "$TEST_TEMP_DIR/git" << 'EOF'
#!/bin/bash
if [[ "$1" == "config" ]]; then
    exit 0
elif [[ "$1" == "apply" && "$3" == "--reverse" ]]; then
    # Patch not yet applied
    exit 1
elif [[ "$1" == "apply" && "$2" == "-v" ]]; then
    # Verbose check with reject
    echo "error: patch failed"
    exit 1
elif [[ "$1" == "apply" ]]; then
    # Any other apply (including --check) fails
    exit 1
fi
exit 0
EOF
    chmod +x "$TEST_TEMP_DIR/git"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "$PATCH_FILE" \
        "deployment-123" \
        "TESTRUN" \
        "test-user" \
        "test@example.com"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Patch cannot be applied"* ]]
}

# --- Tests for unsupported vendor ---

@test "exits with error for unknown vendor" {
    cat > "$TEST_TEMP_DIR/git" << 'EOF'
#!/bin/bash
if [[ "$1" == "config" ]]; then
    exit 0
elif [[ "$1" == "apply" && "$3" == "--reverse" ]]; then
    exit 1
elif [[ "$1" == "apply" && "$3" == "--check" ]]; then
    exit 0
elif [[ "$1" == "apply" ]]; then
    exit 0
fi
exit 0
EOF
    chmod +x "$TEST_TEMP_DIR/git"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "$PATCH_FILE" \
        "deployment-123" \
        "UNKNOWN" \
        "test-user" \
        "test@example.com"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Please use one of the supported Pipeline Vendors"* ]]
}

# --- Tests for git configuration ---

@test "configures git user name and email" {
    cat > "$TEST_TEMP_DIR/git" << 'EOF'
#!/bin/bash
echo "git $@" >> /tmp/git_commands.txt
if [[ "$1" == "apply" && "$3" == "--reverse" ]]; then
    exit 0
fi
exit 0
EOF
    chmod +x "$TEST_TEMP_DIR/git"

    PATH="$TEST_TEMP_DIR:$PATH" run bash "$SCRIPT_PATH" \
        "$PATCH_FILE" \
        "deployment-123" \
        "TESTRUN" \
        "My Name" \
        "my@email.com"

    [ "$status" -eq 0 ]
    grep -q "git config user.name My Name" /tmp/git_commands.txt
    grep -q "git config user.email my@email.com" /tmp/git_commands.txt
    rm -f /tmp/git_commands.txt
}
