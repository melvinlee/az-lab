---
name: work-on-issue
description: Start and finish work on a GitHub issue in this repo end to end. Pull the latest main, branch off it, implement the issue, run the OpenTofu validate loop (fmt, validate, plan; never apply), commit, push, open a PR, and post a summary comment back on the issue. Use whenever the user says "work on issue #N", "start on #4", "pick up issue 12", "implement this issue", pastes a github.com/.../issues/N link, or otherwise asks to do the work an issue describes, even if they don't mention branches, PRs or comments.
---

# Work on a GitHub issue

The whole run should leave a trail someone can follow from the issue: a branch cut from the current `main`, a PR that closes the issue, and a comment on the issue saying what was done and what wasn't. Do the steps in order. If one fails in a way you can't fix, stop and say so instead of skipping ahead.

## 1. Read the issue

Take the issue number from the user's message (a bare `#N`, `N`, or an issue URL).

```sh
gh issue view N --json number,title,body,labels,state,comments,url
```

- If it's **closed**, ask before doing anything.
- Read the comments too. Scope changes often land there instead of in the body.
- If the issue has a checklist, use it as the scope. If it's too big for one PR, say which items you'll do now and which you'll leave, and confirm with the user before you start.

## 2. Start from the latest main

```sh
git status --porcelain          # must be empty
git fetch origin
git switch main
git pull --ff-only origin main
git switch -c <branch>
```

- **Dirty working tree:** stop and ask the user. Don't stash or discard their changes, because they may be in the middle of something.
- **`--ff-only` fails** (local `main` has diverged): stop and report it. Don't reset `main`.
- **Branch name:** `<type>/<N>-<short-slug>`, e.g. `feat/4-keda-addon`. Pick `<type>` from the labels: `enhancement` → `feat`, `bug` → `fix`, `documentation` → `docs`, otherwise `chore`.
- **Branch already exists** (locally or on origin): ask whether to continue on it or start fresh. Earlier work may be on it.

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

Run the bundled script once for each lab directory you touched:

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

**Never run `tofu apply` or `tofu destroy` here.** Applying creates billable Azure resources, and the user reviews the plan first (see CLAUDE.md). The `tfplan` file is gitignored, so leave it in place.

**When plan can't run in full:**
- **No `az login`:** say so in the summary.
- **Destroyed cluster:** `kubectl_manifest` resources need a running cluster. If the cluster is gone, the script plans only the `azurerm_*` resources and prints `PARTIAL plan`. Report it that way: the Kubernetes objects weren't planned, so the issue's in-cluster test cases are still unverified.
- **Empty state:** a plan that shows "everything to add" is expected. Note it.

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

PR: <url> (branch `<branch>`, from main @ <short-sha>)

### Done
- <change> (`path/to/file`)
- ...

### Validation
- fmt: pass · validate: pass · plan: <Plan: X to add, Y to change, Z to destroy | blocked: reason>
- Not applied. Run `tofu apply tfplan` in `<lab-dir>` after reviewing the plan.

### Not done / follow-ups
- <checklist items left, things untested, ideas found along the way>
```

Be honest in "Validation" and "Not done". "plan blocked: cluster not running" is more useful than a vague "validated".

## 7. Report back

Tell the user in a few lines:
- the branch
- the PR link
- the issue comment link (`gh issue comment` prints it)
- the validation outcome
- anything that needs their decision

The next step, applying the plan, is theirs.
