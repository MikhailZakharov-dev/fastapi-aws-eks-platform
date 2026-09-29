# A one-line change that destroys the database: `~` versus `-/+`

- **Symptom:** two edits of the same `aws_db_instance` that look alike give fundamentally
  different results. Changing `identifier` is an in-place update: the database and its
  data survive. Changing `availability_zone` destroys and recreates it: the data dies.
  The configuration alone does not tell them apart.

- **Signal:** `terraform plan` against a database with real data.

  Rename:
  ```
  ~ resource "aws_db_instance" "app" {
      ~ identifier = "talk-booking" -> "talk-booking-db"
        # (72 unchanged attributes hidden)
  Plan: 0 to add, 1 to change, 0 to destroy.
  ```

  Zone change:
  ```
  -/+ resource "aws_db_instance" "app" {
      ~ availability_zone = "eu-central-1b" -> "eu-central-1a" # forces replacement
      ~ master_user_secret = [ { secret_arn = "...rds!db-f2380..." } ] -> (known after apply)
        # (30 unchanged attributes hidden)
  Plan: 1 to add, 0 to change, 1 to destroy.
  ```

- **Cause:** in the provider schema every attribute has a `ForceNew` flag, which reflects
  whether the cloud API can change that property on an existing object. For RDS,
  `availability_zone`, `storage_encrypted`, `kms_key_id`, `engine`, `timezone` and a few
  more are `ForceNew`. `identifier` is not, because AWS has
  `modify-db-instance --new-db-instance-identifier`. Intuition fails here: a "rename"
  sounds riskier than "moving to the neighbouring zone", and in fact it is the other way
  round.

- **What to read in the plan (most reliable first):**
  1. `# forces replacement` — it sits on the guilty line itself and names the cause;
  2. a non-zero number in `N to destroy` — the one figure you must check before
     confirming anything on a stateful resource;
  3. a scatter of `(known after apply)` where there used to be concrete values: a new
     object gets all server-side attributes anew, so hundreds of them become unknown.

- **The blast radius is wider than the database itself:** a replacement changes
  `endpoint`, `master_user_secret.secret_arn` and every output built on them. Not only
  the data breaks, but also the consumers — in our case ESO, which reads the secret by
  its ARN.

- **Fix / Prevention:**
  - set `storage_encrypted` and other `ForceNew` attributes **at creation**: later they
    can only be changed through a snapshot → an encrypted copy → a restore;
  - `lifecycle.prevent_destroy` stops the plan from being built, but its own error
    message names the bypass (`-target`). It is a speed bump against accidents, not a
    barrier against intent;
  - `deletion_protection` works on the AWS side, so it also catches deletion that
    bypasses Terraform — from the console or the CLI;
  - a final snapshot forbids nothing but leaves a restore point.

- **About the restore window:** `backup_retention_period` sets how far back the window
  reaches (1 day for us — the ceiling of a free-plan account), not how fresh the restore
  point is. Transaction logs are shipped about every 5 minutes, so RPO ≈ 5 minutes, and
  within the window you can restore to any moment. When the instance is deleted, the
  automated backups go with it (`delete_automated_backups = true` by default); only the
  final snapshot survives.
