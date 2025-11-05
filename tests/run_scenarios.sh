#!/usr/bin/env bash
set -euo pipefail

# Test harness for magdrago-rust-semver-action
# Creates temporary git repositories and tests various scenarios

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_ROOT="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $*"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local description="$3"
    
    if [ "$expected" = "$actual" ]; then
        log_info "✓ $description: $actual"
        ((TESTS_PASSED+=1))
    else
        log_error "✗ $description: expected '$expected', got '$actual'"
        ((TESTS_FAILED+=1))
    fi
}

setup_test_repo() {
    local repo_dir="$1"
    
    mkdir -p "$repo_dir"
    cd "$repo_dir"
    
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"
    
    # Create a basic Rust project structure
    mkdir -p src
    cat > Cargo.toml << 'EOF'
[package]
name = "test-project"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF
    
    cat > src/main.rs << 'EOF'
fn main() {
    println!("Hello, world!");
}
EOF
    
    # Create source globs file
    mkdir -p .versioning
    cat > .versioning/source_globs.txt << 'EOF'
src/**/*.rs
Cargo.toml
Cargo.lock
EOF
    
    git add .
    git commit -m "Initial commit"
}

run_compute_version() {
    local tag_scope="${1:-v}"
    local source_globs="${2:-.versioning/source_globs.txt}"
    local default_base="${3:-0.1.0}"
    
    # Temporarily set GITHUB_OUTPUT for testing
    local output_file=$(mktemp)
    export GITHUB_OUTPUT="$output_file"
    
    # Unset GitHub Actions environment variables to test local git behavior
    local OLD_GITHUB_REF="${GITHUB_REF:-}"
    local OLD_GITHUB_HEAD_REF="${GITHUB_HEAD_REF:-}"
    unset GITHUB_REF
    unset GITHUB_HEAD_REF
    
    bash "$ACTION_ROOT/scripts/compute_version.sh" "$tag_scope" "$source_globs" "$default_base"
    
    # Restore GitHub Actions environment variables
    if [ -n "$OLD_GITHUB_REF" ]; then
        export GITHUB_REF="$OLD_GITHUB_REF"
    fi
    if [ -n "$OLD_GITHUB_HEAD_REF" ]; then
        export GITHUB_HEAD_REF="$OLD_GITHUB_HEAD_REF"
    fi
    
    # Parse outputs
    NEXT_VERSION=$(grep "next-version=" "$output_file" | cut -d= -f2)
    BUMP_KIND=$(grep "bump-kind=" "$output_file" | cut -d= -f2)
    TAG=$(grep "tag=" "$output_file" | cut -d= -f2)
    PREVIOUS_VERSION=$(grep "previous-version=" "$output_file" | cut -d= -f2)
    
    rm -f "$output_file"
    unset GITHUB_OUTPUT
}

# Test 1: No previous tag, docs-only change
test_no_tag_docs_only() {
    log_test "Test 1: No previous tag, docs-only changes"
    
    local temp_dir=$(mktemp -d)
    setup_test_repo "$temp_dir"
    
    # Add docs-only changes
    echo "# Documentation" > README.md
    git add README.md
    git commit -m "docs: add README"
    
    run_compute_version "v" ".versioning/source_globs.txt" "0.1.0"

    assert_equals "none" "$BUMP_KIND" "Bump kind should be none for docs-only"
    assert_equals "0.1.0" "$NEXT_VERSION" "Version should remain at default"
    assert_equals "0.1.0" "$PREVIOUS_VERSION" "Previous version should use default base"

    cd /
    rm -rf "$temp_dir"
}

# Test 2: No previous tag, source changes (patch)
test_no_tag_source_changes() {
    log_test "Test 2: No previous tag, source changes"
    
    local temp_dir=$(mktemp -d)
    setup_test_repo "$temp_dir"
    
    # Modify source file
    echo 'fn new_function() {}' >> src/main.rs
    git add src/main.rs
    git commit -m "feat: add new function"
    
    run_compute_version "v" ".versioning/source_globs.txt" "0.1.0"
    
    assert_equals "patch" "$BUMP_KIND" "Bump kind should be patch"
    assert_equals "0.1.0" "$NEXT_VERSION" "Version should stay at initial default"
    assert_equals "v0.1.0" "$TAG" "Tag should use initial default"
    assert_equals "0.1.0" "$PREVIOUS_VERSION" "Previous version should use default base"
    
    cd /
    rm -rf "$temp_dir"
}

# Test 3: Feature branch triggers minor bump
test_feature_branch() {
    log_test "Test 3: Feature branch triggers minor bump"
    
    local temp_dir=$(mktemp -d)
    setup_test_repo "$temp_dir"
    
    # Create initial tag
    git tag v1.0.0
    
    # Create and checkout feature branch
    git checkout -b feature/new-feature
    
    # Add source changes
    echo 'fn feature() {}' >> src/main.rs
    git add src/main.rs
    git commit -m "Add feature function"
    
    run_compute_version "v" ".versioning/source_globs.txt" "0.1.0"
    
    assert_equals "minor" "$BUMP_KIND" "Bump kind should be minor on feature branch"
    assert_equals "1.1.0" "$NEXT_VERSION" "Version should be 1.1.0"
    assert_equals "v1.1.0" "$TAG" "Tag should be v1.1.0"
    
    cd /
    rm -rf "$temp_dir"
}

# Test 4: Breaking change triggers major bump
test_breaking_change() {
    log_test "Test 4: Breaking change triggers major bump"
    
    local temp_dir=$(mktemp -d)
    setup_test_repo "$temp_dir"
    
    # Create initial tag
    git tag v2.5.3
    
    # Add breaking change
    echo 'fn breaking() {}' >> src/main.rs
    git add src/main.rs
    git commit -m "feat!: breaking API change"
    
    run_compute_version "v" ".versioning/source_globs.txt" "0.1.0"
    
    assert_equals "major" "$BUMP_KIND" "Bump kind should be major for breaking change"
    assert_equals "3.0.0" "$NEXT_VERSION" "Version should be 3.0.0"
    assert_equals "v3.0.0" "$TAG" "Tag should be v3.0.0"
    assert_equals "2.5.3" "$PREVIOUS_VERSION" "Previous version should be 2.5.3"
    
    cd /
    rm -rf "$temp_dir"
}

# Test 5: Multiple tags, find most recent
test_multiple_tags() {
    log_test "Test 5: Multiple tags, find most recent"
    
    local temp_dir=$(mktemp -d)
    setup_test_repo "$temp_dir"
    
    # Create multiple tags
    git tag v0.5.0
    
    echo 'fn v1() {}' >> src/main.rs
    git add src/main.rs
    git commit -m "Update for v1"
    git tag v1.0.0
    
    echo 'fn v2() {}' >> src/main.rs
    git add src/main.rs
    git commit -m "Update for v2"
    git tag v2.0.0
    
    # Add new changes
    echo 'fn latest() {}' >> src/main.rs
    git add src/main.rs
    git commit -m "Latest change"
    
    run_compute_version "v" ".versioning/source_globs.txt" "0.1.0"
    
    assert_equals "patch" "$BUMP_KIND" "Bump kind should be patch"
    assert_equals "2.0.1" "$NEXT_VERSION" "Version should be 2.0.1"
    assert_equals "2.0.0" "$PREVIOUS_VERSION" "Previous version should be 2.0.0"
    
    cd /
    rm -rf "$temp_dir"
}

# Test 6: Existing tag, no changes
test_no_changes_since_tag() {
    log_test "Test 6: Existing tag, no changes"
    
    local temp_dir=$(mktemp -d)
    setup_test_repo "$temp_dir"
    
    git tag v1.2.3
    
    run_compute_version "v" ".versioning/source_globs.txt" "0.1.0"
    
    assert_equals "none" "$BUMP_KIND" "Bump kind should be none when no changes"
    assert_equals "1.2.3" "$NEXT_VERSION" "Version should remain 1.2.3"
    
    cd /
    rm -rf "$temp_dir"
}

# Test 7: No tags, with Cargo.toml version defined
test_no_tags_with_cargo_version() {
    log_test "Test 7: No tags, Cargo.toml has version 0.5.0"
    
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"
    
    # Create project with specific version in Cargo.toml
    mkdir -p src
    cat > Cargo.toml << 'EOF'
[package]
name = "test-project"
version = "0.5.0"
edition = "2021"

[dependencies]
EOF
    
    cat > src/main.rs << 'EOF'
fn main() {
    println!("Hello, world!");
}
EOF
    
    mkdir -p .versioning
    cat > .versioning/source_globs.txt << 'EOF'
src/**/*.rs
Cargo.toml
Cargo.lock
EOF
    
    git add .
    git commit -m "Initial commit"
    
    # Add a source change
    echo 'fn new_func() {}' >> src/main.rs
    git add src/main.rs
    git commit -m "Add function"
    
    run_compute_version "v" ".versioning/source_globs.txt" "0.1.0"
    
    assert_equals "patch" "$BUMP_KIND" "Bump kind should be patch"
    assert_equals "0.5.0" "$NEXT_VERSION" "Version should use Cargo.toml version (0.5.0), not default-base"
    assert_equals "v0.5.0" "$TAG" "Tag should be v0.5.0"
    assert_equals "0.5.0" "$PREVIOUS_VERSION" "Previous version should be from Cargo.toml"
    
    cd /
    rm -rf "$temp_dir"
}

# Test 8: No tags, no Cargo.toml version (falls back to default-base)
test_no_tags_without_cargo_version() {
    log_test "Test 8: No tags, no Cargo.toml version (uses default-base)"
    
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"
    
    # Create project WITHOUT version in Cargo.toml
    mkdir -p src
    cat > Cargo.toml << 'EOF'
[package]
name = "test-project"
edition = "2021"

[dependencies]
EOF
    
    cat > src/main.rs << 'EOF'
fn main() {
    println!("Hello, world!");
}
EOF
    
    mkdir -p .versioning
    cat > .versioning/source_globs.txt << 'EOF'
src/**/*.rs
Cargo.toml
Cargo.lock
EOF
    
    git add .
    git commit -m "Initial commit"
    
    # Add a source change
    echo 'fn new_func() {}' >> src/main.rs
    git add src/main.rs
    git commit -m "Add function"
    
    run_compute_version "v" ".versioning/source_globs.txt" "0.2.5"
    
    assert_equals "patch" "$BUMP_KIND" "Bump kind should be patch"
    assert_equals "0.2.5" "$NEXT_VERSION" "Version should use default-base when Cargo.toml has no version"
    assert_equals "v0.2.5" "$TAG" "Tag should be v0.2.5"
    assert_equals "0.2.5" "$PREVIOUS_VERSION" "Previous version should be default-base"
    
    cd /
    rm -rf "$temp_dir"
}

# Run all tests
main() {
    log_info "Starting test suite for magdrago-rust-semver-action"
    log_info "Action root: $ACTION_ROOT"
    echo ""
    
    test_no_tag_docs_only
    echo ""
    
    test_no_tag_source_changes
    echo ""
    
    test_feature_branch
    echo ""
    
    test_breaking_change
    echo ""
    
    test_multiple_tags
    echo ""
    
    test_no_changes_since_tag
    echo ""
    
    test_no_tags_with_cargo_version
    echo ""
    
    test_no_tags_without_cargo_version
    echo ""
    
    # Summary
    echo "========================================"
    log_info "Test Summary:"
    log_info "  Passed: $TESTS_PASSED"
    if [ $TESTS_FAILED -gt 0 ]; then
        log_error "  Failed: $TESTS_FAILED"
        exit 1
    else
        log_info "  Failed: $TESTS_FAILED"
        log_info "All tests passed! ✓"
    fi
}

main "$@"

