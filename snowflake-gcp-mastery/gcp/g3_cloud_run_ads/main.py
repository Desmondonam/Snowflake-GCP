"""Cloud Run job: extract yesterday's ad performance and land it in GCS as NDJSON.

In real life `fetch_ad_performance` would call the Google Ads / Meta Marketing APIs.
Here it is a deterministic mock so the course costs nothing and needs no ad accounts,
but everything around it (config, idempotent paths, logging, exit codes) is production-shaped.

Environment variables:
    LANDING_BUCKET   required, e.g. my-project-landing
    RUN_DATE         optional YYYY-MM-DD; default = yesterday (UTC)
    PLATFORMS        optional, default "google,meta"

Local run (needs `gcloud auth application-default login`):
    pip install -r requirements.txt
    LANDING_BUCKET=my-project-landing python main.py
"""
from __future__ import annotations

import json
import logging
import os
import random
import sys
from datetime import date, datetime, timedelta, timezone

from google.cloud import storage

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("ads-extract")

# Same campaign catalogue as the capstone data generator, so the data joins up.
CAMPAIGNS = {
    "google": [
        ("GGL-001", "Brand Search KE"), ("GGL-002", "Brand Search QA"),
        ("GGL-003", "Generic Grocery Search"), ("GGL-004", "Electronics Shopping"),
        ("GGL-005", "Performance Max Apparel"), ("GGL-006", "Back To School"),
    ],
    "meta": [
        ("META-001", "Loyalty Prospecting"), ("META-002", "Retargeting Cart Abandoners"),
        ("META-003", "Weekend Deals"), ("META-004", "Personal Care Video"),
        ("META-005", "Ramadan Offers QA"), ("META-006", "Flash Sale Stories"),
    ],
}


def fetch_ad_performance(platform: str, run_date: date) -> list[dict]:
    """Mock API call. Deterministic per (platform, date) so reruns return the same numbers."""
    rng = random.Random(f"ads|{platform}|{run_date.isoformat()}")
    rows = []
    for campaign_id, campaign_name in CAMPAIGNS[platform]:
        for ad_no in (1, 2):
            spend = round(rng.uniform(40, 400), 2)
            impressions = int(spend * rng.uniform(80, 220))
            clicks = int(impressions * rng.uniform(0.008, 0.04))
            rows.append({
                "date": run_date.isoformat(),
                "platform": platform,
                "campaign_id": campaign_id,
                "campaign_name": campaign_name,
                "ad_id": f"{campaign_id}-AD{ad_no}",
                "ad_name": f"{campaign_name} - Variant {ad_no}",
                "spend": spend,
                "currency": "USD",
                "impressions": impressions,
                "clicks": clicks,
                "conversions": int(clicks * rng.uniform(0.01, 0.06)),
            })
    return rows


def main() -> int:
    bucket_name = os.environ.get("LANDING_BUCKET")
    if not bucket_name:
        log.error("LANDING_BUCKET is not set")
        return 2
    run_date = (
        date.fromisoformat(os.environ["RUN_DATE"])
        if os.environ.get("RUN_DATE")
        else datetime.now(timezone.utc).date() - timedelta(days=1)
    )
    platforms = os.environ.get("PLATFORMS", "google,meta").split(",")
    # Landing files are immutable: every run writes a NEW object (run id in the name).
    # Re-runs therefore never overwrite; staging de-duplicates on (date, ad_id).
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    bucket = storage.Client().bucket(bucket_name)
    for platform in platforms:
        rows = fetch_ad_performance(platform.strip(), run_date)
        payload = "\n".join(json.dumps(r) for r in rows) + "\n"
        path = f"ads/dt={run_date.isoformat()}/ads_{platform}_{run_id}.json"
        bucket.blob(path).upload_from_string(payload, content_type="application/x-ndjson")
        log.info("wrote %d rows to gs://%s/%s", len(rows), bucket_name, path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
