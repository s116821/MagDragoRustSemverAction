<!-- beef76c9-769d-4597-9762-991e000ee264 cac181fd-1ccc-4463-becb-2533c46c9c20 -->
# Implement magdrago-rust-semver Action

1. **Confirm Repository Baseline**  

- Inspect existing files under `MagDragoRustSemverAction` and ensure no conflicting scaffolding.  
- Capture initial git status for reference when coding starts.

2. **Scaffold Action Structure**  

- Add `action.yml` at repo root describing composite action inputs/outputs/steps.  
- Create `scripts/` with helper shell scripts (`compute_version.sh`, `update_and_tag.sh`) to keep composite steps clean.  
- Add `.versioning/example_source_globs.txt` illustrating expected source-glob file format for consumers.

3. **Implement Version Detection Logic**  

- In `scripts/compute_version.sh`, fetch tags by scope, resolve last reachable tag, and derive bump kind based on commit messages, branch naming, and source file diffs.  
- Encode rules: `!` ⇒ major, `feature/*` ⇒ minor, source changes ⇒ patch, else none.  
- Calculate next version (M.N.P) with safe defaults when no prior tag (use `default-base`).  
- Export computed values for downstream steps and GitHub Action outputs.

4. **Handle Cargo Update and Tagging**  

- In `scripts/update_and_tag.sh`, when bump-kind != none:  
• Run `cargo install cargo-edit` if `cargo set-version` unavailable.
• Apply version using `cargo set-version --workspace --exact`.
• Configure git author from action inputs/env, commit with `chore(release): vX.Y.Z`, tag, and push.
- Ensure no-op behavior when bump-kind == none.

5. **Composite Action Wiring**  

- Wire scripts inside `action.yml` steps to call compute logic, set outputs, conditionally call update/tag script, and optionally expose hook for user-provided build commands.  
- Provide sensible defaults, error messaging, and input validation.

6. **Testing Utilities & CI**  

- Add `tests/run_scenarios.sh` to spin up temporary git repos covering cases (docs-only, feature branch, breaking change).  
- Document how to run tests locally (e.g., via `bash tests/run_scenarios.sh`).  
- Add `.github/workflows/test.yml` using `act`-friendly matrix to exercise scripts in CI (optional but recommended per acceptance criteria).

7. **Documentation & Examples**  

- Expand `README.md` with action overview, usage snippet, input/output tables, example workflow, and testing instructions.  
- Reference Linear issue FIN-22 in README changelog/notes for traceability.

### To-dos

- [ ] Review current repo contents and record initial git status before coding
- [ ] Create action.yml, scripts directory, and example source globs file
- [ ] Write compute_version.sh and update_and_tag.sh to implement bump logic and tagging
- [ ] Connect scripts in action.yml with inputs/outputs and optional build hook
- [ ] Add scenario test harness, optional CI workflow, and update README with usage/docs