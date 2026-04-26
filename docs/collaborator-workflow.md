# Collaborator workflow

This is the workflow for anyone using Claude Code as their primary contribution interface to Blaster — Mark, Kurt, future collaborators. Claude manages the full git lifecycle (worktree → commit → push → PR → cleanup) on your behalf. You stay in conversation; you don't run git or `gh` commands yourself.

## Prerequisites (one time per machine)

- macOS Sequoia or later, Xcode 16.3+, iOS 26 simulator
- Claude Code installed: `npm install -g @anthropic-ai/claude-code`
- GitHub CLI installed and authenticated:
  ```sh
  brew install gh
  gh auth login           # GitHub.com → HTTPS → web browser
  ```
  Verify with `gh auth status` — you should see your account and a token with `repo` scope.
- The repo cloned at `~/src/claudeBlast`.

## Starting a feature

1. Open a terminal, `cd ~/src/claudeBlast`.
2. Confirm you're on `main` and clean: `git status`. If not, finish or set aside whatever's pending in the main checkout — it stays there, untouched.
3. Launch a fresh Claude session: `claude`.
4. Describe the feature. Claude will plan first by default; you review and approve the plan before any code is written.

## What Claude does

Once the plan is approved, Claude performs every step of the lifecycle:

1. **Create the worktree** — `EnterWorktree` makes a new branch + checkout under `.claude/worktrees/<name>`. The session switches into that directory.
2. **Implement** — edits files inside the worktree. The main checkout at `~/src/claudeBlast` is untouched.
3. **Build / test** when relevant — runs `xcodebuild ... build` or the test scheme.
4. **Commit** — stages specific files (never `git add -A`), commits with a clear message. Claude confirms with you before staging if anything looks unexpected.
5. **Push** — `git push -u origin <branch>`. Claude confirms before pushing the first time.
6. **Open the PR** — `gh pr create --title ... --body ...` and hands you back the URL. Claude confirms before creating the PR.

## Opening Xcode on the worktree

When you need to run the app, drive SwiftUI previews, or use the simulator against your in-progress branch, open Xcode on the **worktree's checkout**, not the main checkout:

```sh
cd .claude/worktrees/<name>
open claudeBlast.xcodeproj
```

Or ask Claude — `open` is allowed in the project's Claude permissions, so Claude can launch Xcode for you. Both windows can be open at once (worktree branch + main), which is fine; just make sure you're running the right scheme.

## Reviewing and merging

1. Open the PR URL Claude gave you on GitHub.
2. Review the diff. Approve and merge if it's good.
3. Tell Claude: **"PR merged, clean up."**

If you want changes instead of a merge, leave PR comments on GitHub and tell Claude **"address the PR comments"**. Claude reads the comments via `gh pr view --comments`, applies fixes in the same worktree, commits, and pushes — the existing PR updates automatically. Iterate until you merge or close.

## After-merge cleanup

When you say "PR merged, clean up", Claude runs:

1. `ExitWorktree action: "remove"` — deletes the worktree directory and its branch (the branch is already merged into main on GitHub, so this is safe).
2. `git pull` on main — fast-forwards your local main to include the merged PR.

You're back to a clean main checkout, ready for the next feature.

## Troubleshooting

- **`gh auth login` not done.** Claude can't push or open PRs. Run `gh auth login` yourself, then resume.
- **Want to keep the worktree across sessions** (e.g., to come back tomorrow). Tell Claude "exit the worktree but keep it." Claude calls `ExitWorktree action: "keep"`. Re-enter later with `EnterWorktree path: ".claude/worktrees/<name>"`.
- **Abandon a feature mid-flight.** Tell Claude "throw this away." Claude confirms what would be lost, then calls `ExitWorktree action: "remove" discard_changes: true`.
- **Build is broken on main when you start.** Don't enter a worktree on top of broken main — fix main first (or pull a known-good commit), then start the feature.
- **Two parallel features at once.** Open two terminals, launch a separate Claude session in each. Each session enters its own worktree. The branches don't collide.

## Rules of engagement

- Claude **always** confirms before:
  - Pushing a branch for the first time
  - Creating a PR
  - Removing a worktree with `discard_changes: true`
  - Force-pushing (rarely needed; only on explicit request)
- Claude **never** force-pushes to `main` or commits API keys/secrets.
- Direct commits to `main` (no worktree, no PR) are reserved for trivial single-file fixes — typo edits, README tweaks. Anything else uses the worktree+PR flow above.

## Quick reference card

| You say | Claude does |
|---|---|
| Describe a feature | Plans, then enters worktree on approval |
| "Open Xcode on this worktree" | `open claudeBlast.xcodeproj` |
| "Push it" / "Open the PR" | `git push -u origin ...` then `gh pr create`, returns URL |
| "Address the PR comments" | Reads comments, fixes, commits, pushes (updates PR) |
| "PR merged, clean up" | `ExitWorktree remove` + `git pull` on main |
| "Keep the worktree" | `ExitWorktree keep` |
| "Throw this away" | Confirms, then `ExitWorktree remove discard_changes: true` |
