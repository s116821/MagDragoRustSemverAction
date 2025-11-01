# Quick Start Guide

Get up and running with MagDrago Rust Semver Action in 5 minutes.

## Step 1: Create Source Globs File

In your Rust project root, create `.versioning/source_globs.txt`:

```
src/**/*.rs
tests/**/*.rs
Cargo.toml
Cargo.lock
build.rs
```

This tells the action which files are "source code" that should trigger version bumps.

## Step 2: Create Workflow

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    branches: [ main ]

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
      
      - uses: magdrago/magdrago-rust-semver-action@v1
        with:
          source-globs: .versioning/source_globs.txt
      
      - name: Build
        run: cargo build --release
```

## Step 3: Set Permissions

Ensure your workflow has permission to push tags. This is configured in the `permissions:` section above.

## Step 4: Commit Convention (Optional)

For breaking changes, use `!` before the colon:

```bash
git commit -m "feat!: remove deprecated API"
```

For feature branches, use the `feature/` prefix:

```bash
git checkout -b feature/new-thing
```

## Step 5: Push and Watch

```bash
git add .
git commit -m "feat: add versioning workflow"
git push origin main
```

The action will:
1. Detect this is a source code change (patch bump)
2. Update Cargo.toml to the new version
3. Create a git tag (e.g., `v0.1.1`)
4. Push the commit and tag
5. Your workflow continues with the build

## Version Bump Rules

| Trigger | Result | Example |
|---------|--------|---------|
| Commit with `!` | Major bump | 1.2.3 → 2.0.0 |
| `feature/*` branch | Minor bump | 1.2.3 → 1.3.0 |
| Source file changed | Patch bump | 1.2.3 → 1.2.4 |
| Docs only | No bump | 1.2.3 → 1.2.3 |

## Common Scenarios

### First Release

If your repo has no tags, the action uses `0.1.0` by default (or set `default-base` input).

### Dry Run

To test without pushing:

```yaml
- uses: magdrago/magdrago-rust-semver-action@v1
  with:
    source-globs: .versioning/source_globs.txt
    skip-cargo-update: 'true'
```

### Custom Tag Prefix

Use a different tag prefix (default is `v`):

```yaml
- uses: magdrago/magdrago-rust-semver-action@v1
  with:
    source-globs: .versioning/source_globs.txt
    tag-scope: cli-v
```

This creates tags like `cli-v1.2.3`.

### Using Outputs

Access the computed version in subsequent steps:

```yaml
- uses: magdrago/magdrago-rust-semver-action@v1
  id: version
  with:
    source-globs: .versioning/source_globs.txt

- name: Print version
  run: echo "New version is ${{ steps.version.outputs.next-version }}"

- name: Skip if no bump
  if: steps.version.outputs.bump-kind != 'none'
  run: cargo publish
```

## Troubleshooting

**Problem**: "Source globs file not found"  
**Solution**: Ensure `.versioning/source_globs.txt` exists and path is correct

**Problem**: "Permission denied (push)"  
**Solution**: Add `permissions: { contents: write }` to your job

**Problem**: "cargo-set-version not found"  
**Solution**: The action installs it automatically; ensure Rust toolchain is set up first

**Problem**: No version bump when expected  
**Solution**: Check that changed files match patterns in source globs file

## Next Steps

- See [README.md](README.md) for full documentation
- See [example-release.yml.template](.github/workflows/example-release.yml.template) for advanced usage
- See [CONTRIBUTING.md](CONTRIBUTING.md) to contribute
- See [tests/run_scenarios.sh](tests/run_scenarios.sh) for test examples

## Support

- Open an issue on GitHub
- See [Linear FIN-22](https://linear.app/financialfishy/issue/FIN-22) for background

