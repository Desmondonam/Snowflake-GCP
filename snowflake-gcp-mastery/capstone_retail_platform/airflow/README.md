# RetailOne Airflow (local Docker with the Astro CLI)

Runs the nightly pipeline [dags/retail_daily.py](dags/retail_daily.py) on your laptop. The same DAG files deploy
to **Cloud Composer** unchanged (see [stage_05_orchestration/composer_read_through.md](../../stage_05_orchestration/composer_read_through.md)).

## One-time setup

Prerequisites: Docker Desktop running, Astro CLI installed (00_setup), dbt project built once with `--target prod`.

```powershell
cd "D:\Projects\Snowflake GCP\snowflake-gcp-mastery\capstone_retail_platform\airflow"

# 1. Let Astro create its project files around ours (Dockerfile, packages.txt, .astro/, tests/ …).
#    Answer "y" if it warns that the folder is not empty. It keeps our dags/ and requirements.txt.
astro dev init

# 2. Add dbt to the image: append Dockerfile.additions to the generated Dockerfile
Get-Content Dockerfile.additions | Add-Content Dockerfile

# 3. Secrets: the service user's private key + the .env file
mkdir include\keys -Force
copy $HOME\.snowflake\keys\svc_retail_pipeline_rsa_key.p8 include\keys\
copy .env.example .env
code .env        # fill in account, passphrase (twice), Slack webhook (optional)

# 4. Start Airflow (first build takes a few minutes)
astro dev start
```

Open http://localhost:8080 (Astro prints the URL and any login). You should see `retail_daily` and `retail_dbt_cosmos`.

> If `astro dev init` overwrote `requirements.txt`, restore ours with `git checkout requirements.txt`.
> If the dbt folder isn't visible inside the container (`astro dev bash` → `ls include/dbt_retail`), the override mount
> didn't apply: copy instead with `robocopy ..\dbt_retail include\dbt_retail /E /XD target dbt_packages logs`.

## Run it

1. Make sure the business date's data is loaded: `python capstone_retail_platform/data_generator/generate.py new-day --upload`
   (run from the repo root) and note the date it prints.
2. In the UI: `retail_daily` → **Trigger DAG** → *Run with config* → `{"business_date": "<that date>"}`.
3. Watch the Grid view: `wait_for_pos_files` → `dbt_build` → `dbt_reconciliation` → `reconciliation_summary` → `publish_summary`.
4. Open a task's **Logs** to see dbt's output.

### The chaos drill (Capstone 5 evidence)

```powershell
python capstone_retail_platform/data_generator/generate.py new-day --upload --late-store S007
```

Trigger the DAG for that date: `wait_for_pos_files` keeps rescheduling (S007 missing). Then send the late file:

```powershell
python capstone_retail_platform/data_generator/generate.py new-day --upload
```

The sensor succeeds on its next poke, dbt runs, reconciliation passes. Screenshot the Grid view.
To see a reconciliation *failure* instead, set the sensor's timeout low (or mark it success manually) so dbt runs without S007.

## Useful commands

```powershell
astro dev ps          # container status
astro dev logs -s     # scheduler logs
astro dev bash        # shell inside the scheduler container
astro dev restart     # after changing requirements.txt / Dockerfile
astro dev stop        # end of session (frees memory)
astro dev pytest      # run tests in tests/
```

## Design notes (say these in the interview)

- **Airflow orchestrates, Snowflake computes.** Tasks are thin: a SQL check, a dbt command. No data passes through workers.
- **Sensors in `reschedule` mode** free the worker slot between pokes.
- **Idempotent runs**: every run is parameterised by `business_date`; re-running a day re-merges the same rows.
- **dbt in its own venv** avoids dependency conflicts between Airflow providers and dbt adapters.
- **Freshness is informational, reconciliation is blocking**: stale ads data shouldn't stop finance numbers; wrong finance numbers must stop publishing.
- **Secrets**: locally in `.env` + a mounted key file; in Composer, the Secret Manager backend.
