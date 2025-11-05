#!/usr/bin/env bash
set -euo pipefail

# Script to compute semantic version based on git history and commit conventions
# Arguments:
#   $1: tag-scope (e.g., "v")
#   $2: source-globs file path
#   $3: default-base version (e.g., "0.1.0")

TAG_SCOPE="${1:-v}"
SOURCE_GLOBS_FILE="${2}"
DEFAULT_BASE="${3:-0.1.0}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Read source globs from file into array
mapfile -t SOURCE_GLOBS < <(grep -v '^#' "$SOURCE_GLOBS_FILE" | grep -v '^[[:space:]]*$' || true)

if [ ${#SOURCE_GLOBS[@]} -eq 0 ]; then
    log_error "No source globs found in $SOURCE_GLOBS_FILE"
    exit 1
fi

log_info "Loaded ${#SOURCE_GLOBS[@]} source glob patterns"

# Fetch all tags to ensure we have complete history
git fetch --tags --force 2>/dev/null || true

# Find the last reachable tag matching the scope pattern
# Pattern: TAG_SCOPE followed by digits.digits.digits (e.g., v1.2.3)
TAG_PATTERN="^${TAG_SCOPE}[0-9]+\.[0-9]+\.[0-9]+$"

log_info "Looking for tags matching pattern: $TAG_PATTERN"

# Get all tags matching pattern, sorted by version
ALL_TAGS=$(git tag -l "${TAG_SCOPE}*" | grep -E "$TAG_PATTERN" || true)

if [ -z "$ALL_TAGS" ]; then
    log_warn "No existing tags found matching pattern $TAG_PATTERN"
    LAST_TAG=""
    # Parse the default base version
    IFS='.' read -r MAJOR MINOR PATCH <<< "$DEFAULT_BASE"
    PREVIOUS_VERSION="$DEFAULT_BASE"
else
    # Find the most recent reachable tag from current HEAD
    LAST_TAG=""
    for tag in $(echo "$ALL_TAGS" | sort -V -r); do
        if git merge-base --is-ancestor "$tag" HEAD 2>/dev/null; then
            LAST_TAG="$tag"
            break
        fi
    done
    
    if [ -z "$LAST_TAG" ]; then
        log_warn "No reachable tags found from current HEAD"
        # Parse the default base version
        IFS='.' read -r MAJOR MINOR PATCH <<< "$DEFAULT_BASE"
        PREVIOUS_VERSION="$DEFAULT_BASE"
    else
        log_info "Last reachable tag: $LAST_TAG"
        
        # Parse version components from tag
        VERSION_PART="${LAST_TAG#"${TAG_SCOPE}"}"
        IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION_PART"
        PREVIOUS_VERSION="$VERSION_PART"
    fi
fi

# Determine commits to analyze
if [ -n "$LAST_TAG" ]; then
    COMMIT_RANGE="${LAST_TAG}..HEAD"
    log_info "Analyzing commits since $LAST_TAG"
    HAS_PREVIOUS_TAG=true
else
    COMMIT_RANGE="HEAD"
    log_info "Analyzing all commits (no previous tag)"
    HAS_PREVIOUS_TAG=false
fi

# Initialize bump detection
HAS_BREAKING=false
HAS_FEATURE=false
HAS_SOURCE_CHANGES=false

# Check commit messages for breaking changes (! before first colon)
COMMIT_MESSAGES=$(git log "$COMMIT_RANGE" --format="%s" 2>/dev/null || echo "")

if [ -n "$COMMIT_MESSAGES" ]; then
    while IFS= read -r msg; do
        # Check if message contains ! before the first colon
        if [[ "$msg" =~ ^[^:]*! ]]; then
            log_info "Breaking change detected in commit: $msg"
            HAS_BREAKING=true
            break
        fi
    done <<< "$COMMIT_MESSAGES"
fi

# Check current branch name for feature/ prefix
# Try multiple methods to detect the branch name
CURRENT_BRANCH=""

# Method 1: Check local git first (works for local dev and some CI)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Method 2: If HEAD is detached (returns "HEAD"), try GITHUB environment variables
if [ "$CURRENT_BRANCH" = "HEAD" ] || [ -z "$CURRENT_BRANCH" ]; then
    if [ -n "${GITHUB_HEAD_REF:-}" ]; then
        # In pull requests, GITHUB_HEAD_REF contains the source branch
        CURRENT_BRANCH="$GITHUB_HEAD_REF"
        log_info "Branch from GITHUB_HEAD_REF: $CURRENT_BRANCH"
    elif [ -n "${GITHUB_REF:-}" ]; then
        # For push events, GITHUB_REF format: refs/heads/feature/my-feature
        CURRENT_BRANCH="${GITHUB_REF#refs/heads/}"
        log_info "Branch from GITHUB_REF: $CURRENT_BRANCH"
    fi
else
    log_info "Branch from git: $CURRENT_BRANCH"
fi

if [[ "$CURRENT_BRANCH" == feature/* ]]; then
    log_info "Feature branch detected: $CURRENT_BRANCH"
    HAS_FEATURE=true
fi

# Check for source file changes
if [ -n "$LAST_TAG" ]; then
    CHANGED_FILES=$(git diff --name-only "$LAST_TAG" HEAD 2>/dev/null || echo "")
else
    # No previous tag. Compare against the first commit so we only consider
    # changes introduced after the repository baseline instead of every
    # tracked file.
    INITIAL_COMMIT=$(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -n 1)
    if [ -n "$INITIAL_COMMIT" ] && [ "$INITIAL_COMMIT" != "$(git rev-parse HEAD 2>/dev/null)" ]; then
        CHANGED_FILES=$(git diff --name-only "$INITIAL_COMMIT" HEAD 2>/dev/null || echo "")
    else
        CHANGED_FILES=""
    fi
fi

if [ -n "$CHANGED_FILES" ]; then
    # Enable recursive globbing for pattern matching once outside the loops.
    shopt -s globstar nullglob

    while IFS= read -r file; do
        for glob in "${SOURCE_GLOBS[@]}"; do
            match=false

            # shellcheck disable=SC2053
            # Glob matching is intentional here as $glob contains glob patterns
            if [[ "$file" == $glob ]]; then
                match=true
            elif [[ "$glob" == *"**/"* ]]; then
                # Allow patterns like src/**/*.rs to also match src/foo.rs by
                # collapsing the recursive directory matcher when necessary.
                fallback_pattern="${glob//\*\*\/}"  # remove "**/" segments
                # shellcheck disable=SC2053
                # Glob matching is intentional here as $fallback_pattern contains glob patterns
                if [[ -n "$fallback_pattern" && "$file" == $fallback_pattern ]]; then
                    match=true
                fi
            fi

            if [ "$match" = true ]; then
                log_info "Source change detected: $file (matches $glob)"
                HAS_SOURCE_CHANGES=true
                break 2
            fi
        done
    done <<< "$CHANGED_FILES"
fi

# Determine bump kind based on rules
# Priority: major > minor > patch > none
BUMP_KIND="none"

if [ "$HAS_BREAKING" = true ]; then
    BUMP_KIND="major"
    log_info "Bump kind: MAJOR (breaking change detected)"
elif [ "$HAS_FEATURE" = true ]; then
    BUMP_KIND="minor"
    log_info "Bump kind: MINOR (feature branch)"
elif [ "$HAS_SOURCE_CHANGES" = true ]; then
    BUMP_KIND="patch"
    log_info "Bump kind: PATCH (source changes)"
else
    BUMP_KIND="none"
    log_info "Bump kind: NONE (no relevant changes)"
fi

# Compute next version based on bump kind
if [ "$HAS_PREVIOUS_TAG" = true ]; then
    case "$BUMP_KIND" in
        major)
            MAJOR=$((MAJOR + 1))
            MINOR=0
            PATCH=0
            ;;
        minor)
            MINOR=$((MINOR + 1))
            PATCH=0
            ;;
        patch)
            PATCH=$((PATCH + 1))
            ;;
        none)
            # No change
            ;;
    esac

    NEXT_VERSION="${MAJOR}.${MINOR}.${PATCH}"
else
    # First release: always use the provided default base version.
    NEXT_VERSION="$DEFAULT_BASE"
fi

NEXT_TAG="${TAG_SCOPE}${NEXT_VERSION}"

# Output results for GitHub Actions
log_info "Results:"
log_info "  Previous: $PREVIOUS_VERSION"
log_info "  Next:     $NEXT_VERSION"
log_info "  Tag:      $NEXT_TAG"
log_info "  Bump:     $BUMP_KIND"

# Set GitHub Actions outputs
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "next-version=$NEXT_VERSION"
        echo "previous-version=$PREVIOUS_VERSION"
        echo "bump-kind=$BUMP_KIND"
        echo "tag=$NEXT_TAG"
    } >> "$GITHUB_OUTPUT"
else
    # For local testing
    echo "NEXT_VERSION=$NEXT_VERSION"
    echo "PREVIOUS_VERSION=$PREVIOUS_VERSION"
    echo "BUMP_KIND=$BUMP_KIND"
    echo "TAG=$NEXT_TAG"
fi

