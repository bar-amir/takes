# Repository settings

GitHub settings that can't live in files. They record how the repository is meant to be set up for outside contributors, so they can be checked or restored later. Run the commands from the repository folder with `gh` signed in as the owner. Each one is safe to run again.

The security settings (private vulnerability reporting, secret scanning, push protection, code scanning) are covered in [SECURITY.md](../SECURITY.md) and aren't repeated here.

## 1. Discussions (before merging the contributor files)

The issue forms, [SUPPORT.md](../SUPPORT.md) and the discussion templates link to the **Q&A** and **Ideas** categories, so turn Discussions on first.

```bash
gh repo edit bar-amir/takes --enable-discussions
```

GitHub creates the default categories, including Q&A (`q-a`) and Ideas (`ideas`), which the templates in `.github/DISCUSSION_TEMPLATE` match. In **Discussions › Categories**, you can delete Polls and Show and tell if you don't want them. Keep **Announcements**, where only maintainers can post, for release posts.

## 2. Labels

The issue forms and the stale workflow use these labels. Labels that don't exist are silently skipped.

```bash
gh label create "triage" --color FBCA04 --description "New, not looked at yet" --force
gh label create "needs info" --color D4C5F9 --description "Waiting for details from the reporter" --force
gh label create "waiting on author" --color D4C5F9 --description "Pull request waiting for changes from its author" --force
gh label create "stale" --color EDEDED --description "No activity; closes soon unless someone replies" --force
gh label create "app compatibility" --color 1D76DB --description "Reading or pasting fails in a specific app" --force
gh label create "preset" --color C5DEF5 --description "Preset ideas and the preset gallery" --force
gh label create "dependencies" --color 0366D6 --description "Dependency updates (Dependabot)" --force
gh label create "security" --color B60205 --description "Security hardening (never closed as stale)" --force
gh label create "engine" --color 1D76DB --description "Claude Code, API, ChatGPT, provider and local engines" --force
gh label create "english coach" --color 0E8A16 --description "The English coach" --force
```

Keep the existing `windows` and `operations` labels. They track the planned Windows port (#19–#23).

Keep **good first issue** and **help wanted** stocked. GitHub lists them on the repository's `/contribute` page and in its search. A good first issue says which file to change and how to tell it works.

## 3. Pull requests and merging

Squash-merge only, so `main` has one commit per pull request and contributors don't need tidy history. Branches are deleted after merge.

```bash
gh repo edit bar-amir/takes \
  --enable-squash-merge --enable-merge-commit=false --enable-rebase-merge=false \
  --delete-branch-on-merge --enable-auto-merge
gh api -X PATCH repos/bar-amir/takes \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY > /dev/null
```

## 4. CI for pull requests from forks

`build.yml` and `lint.yml` run on `pull_request`. Fork pull requests get a read-only token and no secrets, so they can't reach the signing keys. `cla.yml` uses `pull_request_target` but never checks out the pull request's code. Still, require approval before a newcomer's first CI run, so that macOS runner minutes can't be abused:

```bash
gh api -X PUT repos/bar-amir/takes/actions/permissions/fork-pr-contributor-approval \
  -f approval_policy=first_time_contributors
```

## 5. Protecting `main` with a ruleset

`main` currently uses classic branch protection: build and CLA are required, plus 1 approval from a code owner, with stale approvals dismissed. Rulesets are GitHub's current replacement. A ruleset can sit alongside the "Release tags" ruleset, is visible to contributors, and adds conversation resolution and squash-only merging.

Create the ruleset:

```bash
gh api -X POST repos/bar-amir/takes/rulesets --input - <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "pull_request" }
  ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash"]
    } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "build", "integration_id": 15368 },
          { "context": "CLA", "integration_id": 15368 }
        ]
    } }
  ]
}
JSON
```

Repository admins (actor 5) can still merge their own pull requests without a second reviewer, as they can today, but only through a pull request. `integration_id` 15368 is GitHub Actions, so only the workflows can set those checks.

Once you've seen the ruleset work on one pull request, remove the classic protection so the two don't drift apart:

```bash
gh api -X DELETE repos/bar-amir/takes/branches/main/protection
```

The `Lint` check is advisory and isn't required. Make it required only after the codebase has been formatted once (see 9).

## 6. Limits on unknown contributors

Under **Settings › General › Pull requests**, GitHub (2026) can cap how many open pull requests someone without write access may have in the repository, with a bypass list for trusted contributors. A low cap, such as 3, stops floods of generated pull requests without affecting real contributors.

If a thread or the repository gets flooded, set a temporary interaction limit:

```bash
gh api -X PUT repos/bar-amir/takes/interaction-limits -f limit=existing_users -f expiry=one_week
```

Remove it with `gh api -X DELETE repos/bar-amir/takes/interaction-limits`.

## 7. Discovery: description, website, topics, social preview

```bash
gh repo edit bar-amir/takes \
  --homepage "https://takes.rocks/" \
  --add-topic macos,menu-bar-app,swift,swiftui,writing-assistant,rewrite,proofreading,claude,chatgpt,llm,local-llm,productivity,open-source
```

These can only be set on github.com:

- **Social preview** (Settings › General › Social preview): a 1280×640 PNG. It's what links show in Slack, X and iMessage. Use the hero art from `brand/`.
- **About** sidebar: tick "Releases" and untick "Packages" and "Deployments" to keep it tidy.
- **Wiki** is already off. Turn **Projects** off too (`gh repo edit bar-amir/takes --enable-projects=false`) if you don't use them.

## 8. Health check

**Insights › Community standards** should then show every item as done: description, README, code of conduct, contributing, license, security policy, issue templates and pull request template.

## 9. Later: format the codebase once

`.swift-format` describes the house style, but the existing code doesn't fully match it, so lint only warns about changed files. When no big pull requests are open, run `swift format -i -r Sources Tests` as a single commit, add that commit to a `.git-blame-ignore-revs` file, and make the `Lint` check required.
