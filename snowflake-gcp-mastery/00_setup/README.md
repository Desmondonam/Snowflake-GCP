# 00 — Setup (day 1–2)

Goal: by the end of this page you can run SQL against Snowflake from VSCode and the CLI, Python can talk
to Snowflake and GCS, and you have a budget alert so a mistake never costs you real money.

Work through the steps **in order**. Each step ends with a **✅ Check**. Do not move on until it passes.

---

## Step 1 — Create the accounts

### 1.1 Snowflake trial

1. Go to **signup.snowflake.com**.
2. Edition: **Enterprise**. (Masking policies, multi-cluster warehouses and 90-day Time Travel need it.)
3. Cloud: **Google Cloud Platform**, region **US Central 1 (Iowa)**.
4. Activate from the email, choose a username (e.g. `DESMOND`) and a strong password. Enrol MFA when asked.
5. In Snowsight, click your name (bottom-left) → **Account** → hover the account → **Copy account identifier**.
   It looks like `ABCDEFG-XY12345` (`ORGNAME-ACCOUNTNAME`). Save it; you will need it in Step 6.

✅ Check: in a Snowsight worksheet run `SELECT CURRENT_ACCOUNT(), CURRENT_REGION(), CURRENT_VERSION();`
The region should start with `GCP_US_CENTRAL1`.

### 1.2 Google Cloud

1. Go to **console.cloud.google.com** and start the free trial.
2. Create a project. Name it `retail-dp-lab`. Note the **project ID** under the name (it may get a numeric suffix, e.g. `retail-dp-lab-4821`).
3. **Budget alert (do not skip):** Billing → Budgets & alerts → Create budget → scope: this project → amount **$20** → alerts at 50%, 90%, 100% → Finish.

✅ Check: Billing → Budgets shows your $20 budget.

## Step 2 — Install the tools (Windows)

Open **PowerShell** (not as admin unless winget asks) and run:

```powershell
winget install -e --id Python.Python.3.11
winget install -e --id Git.Git
winget install -e --id Microsoft.VisualStudioCode
winget install -e --id Google.CloudSDK
winget install -e --id Hashicorp.Terraform
winget install -e --id Docker.DockerDesktop
winget install -e --id Astronomer.Astro
```

Close and reopen PowerShell so the new commands are on your PATH, then install the Snowflake CLI with pipx
(pipx keeps CLI tools in their own isolated environment):

```powershell
python -m pip install --user pipx
python -m pipx ensurepath
# close and reopen PowerShell again
pipx install snowflake-cli
```

VSCode extensions (Ctrl+Shift+X and search): **Snowflake** (publisher: Snowflake), **Python**, **dbt Power User**,
**HashiCorp Terraform**, **Docker**, **Rainbow CSV** (handy for checking generated files).

✅ Check: every command prints a version:

```powershell
python --version; git --version; gcloud --version; terraform -version; docker --version; astro version; snow --version
```

> **Shells on Windows.** The `.sh` scripts in this repo run in **Git Bash** (installed with Git) or in
> **Google Cloud Shell** (browser terminal with `gcloud` and `terraform` preinstalled — the easiest option for the GCP track).
> Python, dbt and `snow` commands run in PowerShell.

## Step 3 — Create the repo and the Python environment

```powershell
cd "D:\Projects\Snowflake GCP\snowflake-gcp-mastery"
git init -b main
python -m venv .venv
.\.venv\Scripts\Activate.ps1          # your prompt now starts with (.venv)
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

If PowerShell refuses to run `Activate.ps1`, run once: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

In VSCode: **Ctrl+Shift+P → Python: Select Interpreter → .venv**.

✅ Check: `dbt --version` shows `dbt-core` and the `snowflake` plugin.

## Step 4 — Replace the placeholder

**Ctrl+Shift+H** in VSCode → find `YOUR_PROJECT_ID` → replace with your GCP project ID → Replace All.
(See the root README, section 4.)

## Step 5 — Key-pair authentication (the professional way to connect tools)

Tools (CLI, Python, dbt, Airflow, Terraform) should not log in with your password + MFA. They use an RSA
key pair: the **private key** stays on your machine, Snowflake stores the **public key** on your user.

Open **Git Bash** in the repo folder and run:

```bash
bash 00_setup/generate_keypair.sh desmond              # key for YOU (human user)
bash 00_setup/generate_keypair.sh svc_retail_pipeline  # key for the pipeline service user (used from Stage 1 capstone)
```

You will be asked for a passphrase for each key. Use a strong one and store it in a password manager.
Keys are written to `~/.snowflake/keys/` (outside the repo, so they can never be committed).

The script prints a ready-to-run `ALTER USER` statement. Paste it into a Snowsight worksheet:

```sql
USE ROLE SECURITYADMIN;
ALTER USER DESMOND SET RSA_PUBLIC_KEY = 'MIIBIjANBgkqh...';   -- the value printed by the script
DESC USER DESMOND;   -- RSA_PUBLIC_KEY_FP should now have a value
```

(The service user's key is registered later, in the Stage 1 capstone, after the user exists.)

## Step 6 — Configure the Snowflake CLI and the `.env` file

### 6.1 Snowflake CLI connection

```powershell
mkdir $HOME\.snowflake -Force
copy 00_setup\config.toml.example $HOME\.snowflake\config.toml
code $HOME\.snowflake\config.toml
```

Fill in your account identifier, user and the path to your private key. Then:

```powershell
$env:PRIVATE_KEY_PASSPHRASE = "<your key passphrase>"   # snow CLI reads this variable for encrypted keys
snow connection test
snow sql -q "select current_user(), current_role(), current_warehouse()"
```

The VSCode Snowflake extension can sign in with the same account; use its sign-in panel.

### 6.2 `.env` for Python, dbt and the generator

```powershell
copy 00_setup\.env.example .env
code .env
```

Fill in every value. Then load it into your current PowerShell window (do this at the start of each session):

```powershell
. .\00_setup\load_env.ps1
```

(In Git Bash: `set -a; source .env; set +a`.)

### 6.3 Google Cloud credentials for Python

```powershell
gcloud auth login
gcloud config set project <your-project-id>
gcloud auth application-default login    # lets Python libraries use your identity
```

## Step 7 — Run the environment check

```powershell
python 00_setup/check_env.py
```

You want every line to say `OK`. GCS checks will say `SKIP` until you create the bucket in GCP track G1 — that is expected.

## Common problems

| Symptom | Fix |
| --- | --- |
| `JWT token is invalid` | The public key on the user doesn't match the private key, or the account identifier is wrong. Re-run `DESC USER` and compare `RSA_PUBLIC_KEY_FP` with the fingerprint the script printed. |
| `Password was not given but private key is encrypted` | Set `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE` in `.env` (and `PRIVATE_KEY_PASSPHRASE` for `snow`). |
| `250001: Could not connect … account` | Use `ORGNAME-ACCOUNTNAME` with a hyphen, not the full URL. |
| `DefaultCredentialsError` (Google) | Run `gcloud auth application-default login`. |
| `Activate.ps1 cannot be loaded` | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| `pip install` fails with `No such file or directory … HINT: … Windows Long Path support` | Windows' 260-character path limit (dbt's dependencies have deep paths). Enable long paths once in an **admin** PowerShell: `New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name LongPathsEnabled -Value 1 -PropertyType DWORD -Force`, reboot, retry. Keeping the repo at a short path like `D:\Projects\...` also helps. |
| VSCode shows red "Incorrect syntax near …" on valid SQL | A T-SQL (SQL Server) linter is checking the files. Open the **`snowflake-gcp-mastery` folder itself** (File → Open Folder) so its `.vscode/settings.json` maps `.sql` to Snowflake SQL, and install the recommended extensions when VSCode offers them. |

## Daily routine (keep this)

```powershell
cd "D:\Projects\Snowflake GCP\snowflake-gcp-mastery"
.\.venv\Scripts\Activate.ps1
. .\00_setup\load_env.ps1
```
