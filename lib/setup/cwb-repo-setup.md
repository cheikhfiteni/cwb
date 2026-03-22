Set up cwb for this repository.

Do the repo-level setup that cwb itself cannot do automatically:
- Update the repo root `.gitignore` under a `# cwb ignores` block.
- Ensure that block ignores `.cwb/`, `.cwb.lock`, and any repo-local override files that cwb-generated workflows will create for this repo.
- Keep existing ignore rules intact; merge with an existing `# cwb ignores` block if one already exists.
- Tighten any other repo-local cwb setup that is needed for smooth worktree usage but is not handled directly by the cwb shell wrapper.

Constraints:
- Make the smallest repo-specific changes that fully enable cwb usage here.
- Prefer editing existing docs/config over adding new files unless a new file is clearly necessary.
- Do not change unrelated code.
