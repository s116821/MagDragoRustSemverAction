#!/usr/bin/env bash
set -euo pipefail

# Script to update Cargo.toml, commit, tag, and push
# Arguments:
#   $1: next-version (e.g., "1.2.3")
#   $2: tag (e.g., "v1.2.3")
#   $3: git-user-name
#   $4: git-user-email

NEXT_VERSION="${1}"
TAG="${2}"
GIT_USER_NAME="${3}"
GIT_USER_EMAIL="${4}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Validate inputs
if [ -z "$NEXT_VERSION" ] || [ -z "$TAG" ]; then
    log_error "Missing required arguments: next-version and tag"
    exit 1
fi

log_info "Updating Cargo.toml to version $NEXT_VERSION"

# Check if cargo set-version is available
if ! command -v cargo-set-version &> /dev/null; then
    log_error "cargo-set-version not found. Please install cargo-edit."
    exit 1
fi

# Update version in Cargo.toml
if ! cargo set-version --workspace --exact "$NEXT_VERSION"; then
    log_error "Failed to update Cargo.toml version"
    exit 1
fi

log_info "Successfully updated Cargo.toml"

# Configure git
git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

log_info "Configured git user: $GIT_USER_NAME <$GIT_USER_EMAIL>"

# Stage Cargo.toml files
git add Cargo.toml
# Also stage any workspace member Cargo.toml files
git add '**/Cargo.toml' 2>/dev/null || true

log_info "Staged Cargo.toml changes"

# Commit with conventional commit message
COMMIT_MESSAGE="chore(release): $TAG"
git commit -m "$COMMIT_MESSAGE"

log_info "Committed changes: $COMMIT_MESSAGE"

# Create annotated tag
git tag -a "$TAG" -m "Release $TAG"

log_info "Created annotated tag: $TAG"

# Push commit and tag
# Note: This assumes the workflow has proper permissions
log_info "Pushing commit and tag to remote..."

if ! git push origin HEAD; then
    log_error "Failed to push commit"
    exit 1
fi

if ! git push origin "$TAG"; then
    log_error "Failed to push tag"
    exit 1
fi

log_info "Successfully pushed commit and tag"
log_info "Release $TAG complete!"

