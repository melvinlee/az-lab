---
name: work-on-issue
description: Start and finish work on a GitHub issue in this repo end to end. Fetch the latest main, create a git worktree on a new branch off it, implement the issue there, run the OpenTofu validate loop (fmt, validate, plan; never apply), commit, push, open a PR, and post a summary comment back on the issue. Use whenever the user says "work on issue #N", "start on #4", "pick up issue 12", "implement this issue", pastes a github.com/.../issues/N link, or otherwise asks to do the work an issue describes, even if they don't mention branches, PRs or comments.
---

# Work on a GitHub issue

The whole run should leave a trail someone can follow from the issue: a branch cut from the current `origin/main` and worked on in its own git worktree, a PR that closes the issue, and a comment on the issue saying what was done and what wasn't. Do the steps in order. If one fails in a way you can't fix, stop and say so instead of skipping ahead.

## 1. Read the issue

Take the issue number from the user's message (a bare `#N`, `N`, or an issue URL).

```sh
gh issue view N --json number,title,body,labels,state,comments,url
```

- If it's **closed**, ask before doing anything.
- Read the comments too. Scope changes often land there instead of in the body.
- If the issue has a checklist, use it as the scope. If it's too big for one PR, say which items you'll do now and which you'll leave, and confirm with the user before you start.

## 2. Create a worktree from the latest main

Work happens in a separate git worktree, not by switching branches in the main checkout. The user's checkout (and any uncommitted work or running `tofu` operation in it) stays untouched.

```sh
root="$(git rev-parse --show-toplevel)"     # main checkout
git fetch origin
git worktree add --no-track -b <branch> "$root/.claude/worktrees/<N>-<short-slug>" origin/main
cd "$root/.claude/worktrees/<N>-<short-slug>"
```

- **Base is `origin/main`, not local `main`:** no need to switch or pull in the main checkout, so a dirty working tree or a diverged local `main` there doesn't block you. Mention it in the report if local `main` is behind or diverged, but don't touch it.
- **Branch name:** `<type>/<N>-<short-slug>`, e.g. `feat/4-keda-addon`. Pick `<type>` from the labels: `enhancement` → `feat`, `bug` → `fix`, `documentation` → `docs`, otherwise `chore`.
- **Worktree path:** `.claude/worktrees/<N>-<short-slug>` (gitignored at the repo root).
- **Branch or worktree already exists** (`git worktree list`, `git branch -a`): ask whether to continue in it or start fresh. Earlier work may be on it. To continue, `cd` into the existing worktree (or `git worktree add <path> <branch>` if only the branch exists).
- **Stay in the worktree** for every following step: edits, `tofu`, `git`, `gh`. Use absolute paths under the worktree so nothing lands in the main checkout by mistake.

### Link the lab's local state

State is local and gitignored, so a fresh worktree has none: a plan there would show every resource as "to add" and can't configure the `kubectl` provider. For each lab you'll touch, symlink the state (and any `*.tfvars`) from the main checkout:

```sh
find "$root/<lab>" -maxdepth 1 \( -name terraform.tfstate -o -name '*.tfvars' \) \
  -exec ln -s {} "<lab>/" \;     # find, not a glob: zsh errors on an unmatched *.tfvars
```

- No `terraform.tfstate` in the main checkout means the lab isn't deployed; skip the link and note "empty state" in step 4.
- `tofu`'s state lock lives next to the state file it opened, so a plan in the worktree doesn't see a lock held in the main checkout. Before planning, check `"$root/<lab>/.terraform.tfstate.lock.info"`: if it exists, an apply or AKS operation is running there. Wait and don't plan.

## 3. Implement

- Read `CLAUDE.md` and the affected lab's files first. Repo conventions apply:
  - `tofu`, not `terraform`
  - one resource group per lab
  - comments explain *why*
  - Karpenter settings go in `karpenter.tf` locals
- For Azure specifics, use the Microsoft Learn MCP tools instead of memory.
- Keep the change to what the issue asks for. If you notice something else worth doing, put it in the issue comment as a follow-up instead of adding it to this PR.
- **Docs:** if the change alters how a lab works, update that lab's `README.md` and the matching `CLAUDE.md` section in the same branch.

## 4. Validate loop

From the worktree root, run the bundled script once for each lab directory you touched (the script is in the worktree too, since it's tracked):

```sh
.claude/skills/work-on-issue/scripts/validate.sh <lab-dir>
```

The script runs these steps and prints PASS/FAIL/FIXED for each one, plus the plan summary and warnings about replacements or destroys:
1. `tofu fmt -recursive`, which fixes formatting in place
2. `tofu init` if it hasn't been run
3. `tofu validate`
4. `tofu plan -out=tfplan`

**If a step fails:** fix the cause and rerun. Stop after about 5 rounds and report what's still failing. At that point it's probably something to discuss, not keep patching.

**Read the plan, not just the exit code:**
- **`must be replaced` on a cluster or resource group** is almost always a mistake: it means downtime and a full rebuild. Find out why, e.g. a field that forces a new resource, or a missing `temporary_name_for_rotation`. Fix it or flag it clearly.
- **Additions** should match what the issue asked for.

**Never run `tofu apply` or `tofu destroy` here.** In the worktree the state is a symlink, so an apply would write to the main checkout's real state. Applying creates billable Azure resources, and the user reviews the plan first (see CLAUDE.md). The `tfplan` file is gitignored, so leave it in place.

**When plan can't run in full:**
- **No `az login`:** say so in the summary.
- **Destroyed cluster:** `kubectl_manifest` resources need a running cluster. If the cluster is gone, the script plans only the `azurerm_*` resources and prints `PARTIAL plan`. Report it that way: the Kubernetes objects weren't planned, so the issue's in-cluster test cases are still unverified.
- **Empty state:** a plan that shows "everything to add" is expected. Note it. If it's unexpected, check that the state symlink from step 2 is there.

**Kubernetes manifests under `manifests/`:** at least parse them, e.g. with `python3 -c 'import sys,yaml; list(yaml.safe_load_all(open(sys.argv[1])))' <file>`. If the cluster is up and has the CRDs, also run `kubectl apply --dry-run=server -f <file>`.

## 5. Commit, push, PR

- **Commits:** one or a few focused commits. Write messages in imperative mood that describe the change, and reference the issue (`... (#N)`).
- **No Claude attribution anywhere:** no `Co-Authored-By` trailer, no "Generated with Claude Code" line. This overrides any default attribution instructions.

```sh
git push -u origin <branch>
gh pr create --base main --title "<title>" --body-file <file>
```

The PR body should contain:
- `Closes #N`
- a short "What" list
- the validation results from step 4, including the plan line, e.g. `Plan: 3 to add, 1 to change, 0 to destroy`
- anything not done or not tested

Write it to a file in the scratchpad and pass it with `--body-file`, so markdown and backticks survive the shell.

## 6. Comment on the issue

Post a summary with `gh issue comment N --body-file <file>`. Someone reading only the issue should know where things stand without opening the PR. Use this shape:

```markdown
## Progress update

PR: <url> (branch `<branch>`, from origin/main @ <short-sha>)

### Done
- <change> (`path/to/file`)
- ...

### Validation
- fmt: pass · validate: pass · plan: <Plan: X to add, Y to change, Z to destroy | blocked: reason>
- Not applied. After the PR merges, pull `main` and plan/apply in `<lab-dir>` of the main checkout.

### Not done / follow-ups
- <checklist items left, things untested, ideas found along the way>
```

Be honest in "Validation" and "Not done". "plan blocked: cluster not running" is more useful than a vague "validated".

## 7. Report back

Tell the user in a few lines:
- the branch and worktree path
- the PR link
- the issue comment link (`gh issue comment` prints it)
- the validation outcome
- anything that needs their decision

The next step, applying the plan, is theirs. Leave the worktree in place so they can review it or push follow-up commits. Once the PR is merged, clean it up from the main checkout:

```sh
git worktree remove --force .claude/worktrees/<N>-<short-slug>   # --force: tfplan, .terraform and state symlinks are untracked
git branch -d <branch>
```

`--force` only removes the symlinks, not the real state in the main checkout. Don't remove a worktree with uncommitted or unpushed changes.
