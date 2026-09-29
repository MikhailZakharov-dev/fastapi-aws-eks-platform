# A secret in git history: deleting the file is not enough

- **Symptom:** a file with credentials was committed and pushed. The next commit deleted
  it — it is gone from the working tree, but the scanner still fails.

- **Signal:** the `secrets` job (gitleaks) on two consecutive runs. Both times the
  finding points to **the same commit** — the one where the file appeared — although the
  second run was already on a commit without the file:

  ```
  Finding:     DB_PASSWORD=REDACTED
  File:        .env.production
  Commit:      1ddc3aa3d109be9f69d8d1a7b20a5b1b73952543
  Link:        https://gitlab.com/.../blob/1ddc3aa3.../.env.production#L1
  27 commits scanned. leaks found: 1
  ```

  The link in the output works: the value opens in the web interface by the commit
  hash, even though the file is absent from HEAD.

- **Cause:** a commit is immutable, and deleting a file creates a new snapshot without
  touching the previous ones. The value stays an object in the repository, reachable by
  hash. On top of that it has already spread: clones, forks, CI caches, the host's
  backups, other developers' local copies.

- **Fix (order matters):**
  1. **Rotate the value at the source** — the mandatory first step. Only this makes the
     leaked value useless. Cleaning history may not work at all, while rotation works no
     matter how many copies are out there.
  2. **Rewrite history** (`git filter-repo` or BFG + force-push) — the second step, and
     an expensive one: it breaks existing clones and needs coordination. It makes sense
     for a private repository with a known set of copies.
  3. **Add the finding's fingerprint to `.gitleaksignore`** — if history will not be
     rewritten but the incident is handled. Otherwise one old commit blocks the pipeline
     forever.

- **Prevention:**
  - Scan history in CI (`gitleaks git`), not just the working tree. Always with
    `GIT_DEPTH: 0`: with the default shallow clone, a finding in an old commit is not
    detected.
  - `--redact` in the scanner command: otherwise the found value is printed into the
    pipeline log, and the anti-leak tool leaks it itself.
  - Secrets should not get into the repository at all. `.gitignore` does not protect from
    that — in this incident the file was added with `git add -f`, one flag. Only delivery
    from an external source (see ADR 21) works, with the scanner as a safety net.

- **About the failure class:** the first version of the scanner job failed with
  `unknown command "sh" for "gitleaks"`. The image has an `ENTRYPOINT` with the binary
  itself, while the runner starts `script` through a shell. Fixed with
  `entrypoint: [""]`. The error comes from the launch layer, not from the tool: the tool
  never started.
