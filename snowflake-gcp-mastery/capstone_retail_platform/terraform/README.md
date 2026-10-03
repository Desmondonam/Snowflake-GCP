# RetailOne infrastructure in one Terraform apply (GCP + Snowflake)

| File | Owns |
| --- | --- |
| [gcp.tf](gcp.tf) | APIs + the landing-zone module from the GCP track (buckets, Pub/Sub, notification, SAs, Cloud Run job, scheduler) |
| [snowflake.tf](snowflake.tf) | Resource monitor, 4 warehouses, 5 databases, 3 roles + hierarchy, ownership, privileges, service user |
| [integrations.tf](integrations.tf) | Storage + notification integrations **and** the GCP IAM grants for Snowflake's service accounts |
| [versions.tf](versions.tf) | Providers: `google`, and `snowflake` three times (SYSADMIN / SECURITYADMIN / ACCOUNTADMIN aliases) |

Not here on purpose: RAW tables, pipes, streams, tasks, dynamic tables, policies → [../snowflake/deploy.py](../snowflake/deploy.py);
models → dbt. Rule of thumb: Terraform for **account-level, slow-changing** objects; migrations and dbt for **schema-level** ones.

## First apply

```powershell
cd "D:\Projects\Snowflake GCP\snowflake-gcp-mastery\capstone_retail_platform\terraform"
copy terraform.tfvars.example terraform.tfvars      # fill it in
$env:TF_VAR_snowflake_private_key_passphrase = "<your key passphrase>"
gcloud auth application-default login               # Terraform's Google credentials
```

1. **Hand over** objects that SQL created earlier (destructive — read the header first):
   run [handover_from_sql.sql](handover_from_sql.sql) in Snowsight, and `terraform destroy` in `gcp/terraform` if you applied the GCP capstone.
2. Plan and apply:

   ```powershell
   terraform init
   terraform fmt -recursive
   terraform validate
   terraform plan -out tf.plan       # read it: ~60 resources to add
   terraform apply tf.plan
   ```

3. Follow the `next_steps` output (deploy SQL objects, backfill RAW, dbt build, governance).

## Acceptance test 5 — destroy and rebuild

```powershell
terraform destroy          # removes buckets (force_destroy) and every Snowflake object above
terraform apply            # rebuilds; then the next_steps sequence
```

Because the landing bucket is destroyed too, regenerate data afterwards:
`python capstone_retail_platform/data_generator/generate.py backfill --days 90 --upload` (pipes exist after `deploy.py --phase pre`).

## If validate/plan errors

The Snowflake provider renames arguments between major versions. Read the error, open the docs for the
installed version (`terraform version` shows it; registry.terraform.io/providers/snowflakedb/snowflake/<version>/docs),
and fix the argument name. Integrations are *preview* resources in the provider and must stay listed in
`preview_features_enabled` (versions.tf).

## Good practice notes

- State: local here; in a team use a GCS backend with versioning and state locking.
- Secrets: the passphrase comes from `TF_VAR_…`, never from a committed file.
- One user with three roles for the lab. In production, a dedicated `SVC_TERRAFORM` user with a custom role holding exactly the needed account privileges, running from CI.
