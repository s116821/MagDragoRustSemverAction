# MagDrago Rust Semver Action

[![Test Action](https://github.com/magdrago/MagDragoRustSemverAction/workflows/Test%20Action/badge.svg)](https://github.com/magdrago/MagDragoRustSemverAction/actions)

A reusable GitHub Action that automates semantic versioning for Rust CLI packages. This action computes version bumps based on git history, commit conventions, and file changes, then updates `Cargo.toml`, creates git tags, and pushes changes—eliminating manual version management.

> **Note:** This action is specifically designed for **Rust CLI packages** which use three-part semantic versioning (`M.N.P`). For more complex scenarios including services with four-part versioning, see the [magdrago-semver CLI tool](https://github.com/magdrago/magdrago-semver).

**📚 New to this action?** Check out the [Quick Start Guide](docs/QUICKSTART.md) to get up and running in 5 minutes!

## Features

- 🚀 **Automatic version computation** based on commit messages and file changes
- 🔖 **Smart tagging** with configurable tag prefixes
- 📦 **Cargo.toml updates** via `cargo-edit`
- 🌿 **Branch-aware** versioning (feature branches trigger minor bumps)
- 💥 **Breaking change detection** using conventional commits
- 🎯 **Source file filtering** via glob patterns
- 🔍 **No-op when no relevant changes** detected
- 📊 **Detailed GitHub Actions summary output**

## Version Computation Rules

The action follows these prioritized rules to determine version bumps:

| Priority | Trigger | Bump Type | Example |
|----------|---------|-----------|---------|
| 1 | `!` before first `:` in commit message | **Major** | `1.2.3` → `2.0.0` |
| 2 | Branch name starts with `feature/` | **Minor** | `1.2.3` → `1.3.0` |
| 3 | Source files changed (matching globs) | **Patch** | `1.2.3` → `1.2.4` |
| 4 | No relevant changes | **None** | No version bump |

When a bump occurs, all lesser version components reset to zero (e.g., major bump resets minor and patch to 0).

## First Run Behavior

When no git tags exist yet, the action uses intelligent version detection:

1. **Checks `Cargo.toml` first**: If your `Cargo.toml` has a version (e.g., `0.5.0`), the action uses that version
   - Creates a git tag for that version (e.g., `v0.5.0`)
   - **No file changes needed** - avoids "nothing to commit" errors
   - Ideal when you've manually set an initial version

2. **Falls back to `default-base`**: If `Cargo.toml` has no version field, uses the `default-base` parameter (default: `0.1.0`)
   - Creates a git tag (e.g., `v0.1.0`)
   - Updates `Cargo.toml` to that version
   - Ideal for brand new projects

3. **Subsequent runs**: After the first tag exists, normal bump rules apply based on changes

### Example Scenarios

| Scenario | Cargo.toml | Git Tags | Action Behavior |
|----------|------------|----------|-----------------|
| **New project, no version** | No `version` field | None | Uses `default-base`, creates tag, writes to Cargo.toml |
| **Manually versioned** | `version = "0.5.0"` | None | Uses `0.5.0`, creates `v0.5.0` tag, no file change |
| **Tagged project** | `version = "1.2.3"` | `v1.2.3` exists | Bumps from `v1.2.3` based on changes (normal operation) |

## Usage

### Basic Example

```yaml
name: Release

on:
  push:
    branches: [ main ]

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write  # Required for creating tags and pushing
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Required for tag history
      
      - name: Set up Rust
        uses: actions-rs/toolchain@v1
        with:
          profile: minimal
          toolchain: stable
          override: true
      
      - name: Compute version and tag
        uses: magdrago/magdrago-rust-semver-action@v1
        with:
          source-globs: .versioning/source_globs.txt
          tag-scope: v
      
      - name: Build release
        if: steps.compute.outputs.bump-kind != 'none'
        run: cargo build --release
      
      - name: Create GitHub Release
        if: steps.compute.outputs.bump-kind != 'none'
        uses: softprops/action-gh-release@v1
        with:
          tag_name: ${{ steps.compute.outputs.tag }}
          files: target/release/*
```

### Advanced Example with Custom Configuration

```yaml
- name: Version and release
  id: version
  uses: magdrago/magdrago-rust-semver-action@v1
  with:
    source-globs: .versioning/source_globs.txt
    tag-scope: cli-v
    default-base: 1.0.0
    git-user-name: Release Bot
    git-user-email: bot@example.com
    skip-cargo-update: false

- name: Use version outputs
  run: |
    echo "Previous: ${{ steps.version.outputs.previous-version }}"
    echo "Next: ${{ steps.version.outputs.next-version }}"
    echo "Bump: ${{ steps.version.outputs.bump-kind }}"
    echo "Tag: ${{ steps.version.outputs.tag }}"
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `source-globs` | Path to file with source glob patterns (newline-delimited) | ✅ Yes | - |
| `tag-scope` | Prefix for matching/creating tags | No | `v` |
| `default-base` | Fallback version when no tags exist AND Cargo.toml has no version (M.N.P format) | No | `0.1.0` |
| `git-user-name` | Git user name for commits | No | `github-actions[bot]` |
| `git-user-email` | Git user email for commits | No | `github-actions[bot]@users.noreply.github.com` |
| `skip-cargo-update` | Skip updating Cargo.toml (for dry-run) | No | `false` |

## Outputs

| Output | Description | Example |
|--------|-------------|---------|
| `next-version` | Computed semantic version | `1.2.3` |
| `bump-kind` | Type of bump: `major`, `minor`, `patch`, or `none` | `patch` |
| `tag` | Full tag name | `v1.2.3` |
| `previous-version` | Version before bump | `1.2.2` |

## Repository Setup

### 1. Create Source Globs File

Create `.versioning/source_globs.txt` in your repository to define which files are considered "source" files:

```
# Rust source files
src/**/*.rs
tests/**/*.rs
benches/**/*.rs
examples/**/*.rs

# Cargo configuration
Cargo.toml
Cargo.lock

# Build scripts
build.rs
```

See [.versioning/example_source_globs.txt](.versioning/example_source_globs.txt) for a template.

### 2. Configure Workflow Permissions

Ensure your workflow has permission to push commits and tags:

```yaml
permissions:
  contents: write
```

### 3. Use Conventional Commits (Optional but Recommended)

For breaking changes, use the `!` syntax before the first colon:

```bash
git commit -m "feat!: remove deprecated API"
git commit -m "refactor!: restructure module exports"
```

## Testing

### Run Local Tests

```bash
# Make scripts executable (Unix-like systems)
chmod +x scripts/*.sh tests/*.sh

# Run test scenarios
bash tests/run_scenarios.sh
```

The test harness creates temporary git repositories and validates version computation logic across multiple scenarios:
- Docs-only changes (no bump)
- Source file changes (patch bump)
- Feature branches (minor bump)
- Breaking changes (major bump)
- Multiple tags (finds most recent)
- No changes since last tag (no bump)

### CI Testing

The action includes comprehensive CI testing via `.github/workflows/test.yml`:
- Scenario-based unit tests
- Integration tests with real Rust projects
- ShellCheck linting for all scripts

## How It Works

1. **Fetch and analyze git history**: Finds the most recent reachable tag matching the tag scope pattern
2. **Detect changes**: Examines commits, branch names, and changed files since the last tag
3. **Compute bump**: Applies versioning rules based on findings
4. **Update Cargo.toml**: Uses `cargo set-version` to update all workspace packages
5. **Commit and tag**: Creates a conventional commit and annotated git tag
6. **Push**: Pushes both commit and tag to remote

## Acceptance Criteria (FIN-22)

- ✅ Computes correct versions according to specified rules
- ✅ No bump for docs-only changes
- ✅ Minor bump for feature branches with code changes
- ✅ Major bump for commits with `!` in message
- ✅ Updates Cargo.toml, commits, creates tag, and pushes
- ✅ Comprehensive README with usage instructions
- ✅ Three-part semantic versioning (M.N.P) for Rust packages

## Related Projects

- **[magdrago-semver CLI](https://github.com/magdrago/magdrago-semver)** - Full-featured Rust CLI tool supporting packages, services, and advanced tagging strategies (FIN-23)
- **Integration Guides**:
  - [Python Projects (FIN-24)](https://linear.app/financialfishy/issue/FIN-24)
  - [TypeScript Projects (FIN-25)](https://linear.app/financialfishy/issue/FIN-25)
  - [C++ Projects (FIN-26)](https://linear.app/financialfishy/issue/FIN-26)

## Contributing

Contributions are welcome! Please ensure:
- All scripts pass ShellCheck linting
- Test scenarios cover your changes
- Documentation is updated

## License

See [LICENSE](LICENSE) for details.

## References

- **Linear Issue**: [FIN-22 - Build GitHub Action: magdrago-rust-semver-action](https://linear.app/financialfishy/issue/FIN-22)
- **Semantic Versioning**: [semver.org](https://semver.org/)
- **Conventional Commits**: [conventionalcommits.org](https://www.conventionalcommits.org/)
