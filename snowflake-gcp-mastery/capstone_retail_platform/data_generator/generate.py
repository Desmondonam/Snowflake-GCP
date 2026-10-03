"""RetailOne synthetic data generator.

Produces realistic, deterministic fake data for a retailer with 20 stores in Kenya and Qatar,
an online shop, a loyalty programme (CRM), an ERP and paid ads on Google and Meta, laid out
exactly like a real landing zone:

    <output>/<source>/dt=YYYY-MM-DD/<file>

    pos_sales/       store_<id>.csv           POS line items (one file per store per day)
    pos_control/     control_totals.csv       POS "Z-report" totals per store-day (for reconciliation)
    ecom_orders/     orders.parquet           online order lines (schema change on purpose after day 60)
    crm_customers/   customers.json           NDJSON: full extract on day 1, then daily changes (CDC-like)
    erp_products/    products.csv             full extract on day 1, then daily price changes
    erp_stores/      stores.csv               day 1 only
    erp_inventory/   inventory.csv            opening stock per store x sku x day
    ads/             ads_<platform>_<run>.json NDJSON daily ad performance (Google, Meta)
    web_events/      events.json              NDJSON clickstream incl. ad clicks, email opens, purchases
    reviews/         reviews.json             NDJSON product reviews (Cortex sentiment in Stage 8)

Everything is deterministic (seeded by date), so re-running produces identical files, and the
"new-day" mode continues the same world day after day.

Usage (repo root, venv active, .env loaded):
    python capstone_retail_platform/data_generator/generate.py backfill --days 90 --upload
    python capstone_retail_platform/data_generator/generate.py new-day --upload
    python capstone_retail_platform/data_generator/generate.py new-day --upload --late-store S007
    python capstone_retail_platform/data_generator/generate.py new-day --upload --inject-bad-file --duplicate-file
    python capstone_retail_platform/data_generator/generate.py change-tier --customer-id C00042 --tier PLATINUM
    python capstone_retail_platform/data_generator/generate.py status
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import random
import re
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

import pandas as pd
from dotenv import find_dotenv, load_dotenv
from faker import Faker

# ---------------------------------------------------------------------------
# World configuration
# ---------------------------------------------------------------------------
SEED = 20261003
N_STORES_KE, N_STORES_QA = 12, 8
N_SKUS = 500
N_CUSTOMERS = 5000
N_GUESTS = 1500
SCHEMA_CHANGE_AFTER_DAYS = 60  # ecom_orders gains a `delivery_method` column from this day on

KE_CITIES = ["Nairobi", "Mombasa", "Kisumu", "Nakuru", "Eldoret"]
QA_CITIES = ["Doha", "Al Rayyan", "Al Wakrah", "Lusail"]
CATEGORIES = {
    "Grocery": (["Rice & Grains", "Dairy", "Snacks", "Bakery"], (0.5, 15.0)),
    "Beverages": (["Soft Drinks", "Juice", "Water", "Coffee & Tea"], (0.4, 12.0)),
    "Household": (["Cleaning", "Kitchen", "Laundry"], (1.0, 30.0)),
    "Personal Care": (["Hair Care", "Skin Care", "Oral Care"], (1.0, 25.0)),
    "Electronics": (["Phones", "Accessories", "Audio"], (8.0, 400.0)),
    "Apparel": (["Men", "Women", "Kids"], (5.0, 80.0)),
}
BRANDS = ["Savanna", "Acacia", "Dunes", "Baobab", "Pearl", "Kilima", "Oasis", "Simba", "Falcon", "Jua"]
PROMOS = {"PROMO10": 0.10, "WEEKEND15": 0.15, "LOYAL20": 0.20, "FLASH25": 0.25}
TENDERS = {"KE": ["CASH", "CARD", "MPESA", "MPESA"], "QA": ["CASH", "CARD", "CARD", "WALLET"]}
SEGMENTS = (["VALUE", "MAINSTREAM", "PREMIUM"], [40, 45, 15])
TIERS = (["BRONZE", "SILVER", "GOLD", "PLATINUM"], [50, 30, 15, 5])
ORDER_STATUS = (["DELIVERED", "SHIPPED", "PLACED", "CANCELLED", "RETURNED"], [70, 12, 8, 6, 4])
DELIVERY_METHODS = ["HOME_DELIVERY", "CLICK_AND_COLLECT", "EXPRESS"]
CHANNELS = (["paid_search", "paid_social", "email", "organic", "direct"], [30, 25, 20, 15, 10])

# Must match gcp/g3_cloud_run_ads/main.py so the Cloud Run job and the generator agree.
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

REVIEW_TEMPLATES = {
    5: ["Absolutely love this {p}. Great quality and fast delivery.",
        "The {p} exceeded my expectations, will buy again!",
        "Excellent value. My family uses the {p} every day."],
    4: ["Good {p}, works as described. Packaging could be better.",
        "Happy with the {p}. Slightly pricey but worth it."],
    3: ["The {p} is okay. Nothing special for the price.",
        "Average {p}. Delivery took longer than promised."],
    2: ["Disappointed with the {p}. Quality is not what I expected.",
        "The {p} stopped working after a week, support was slow."],
    1: ["Terrible {p}. Arrived damaged and the refund took weeks.",
        "Worst purchase this year. The {p} is poor quality, avoid."],
}

POS_HEADER = ["transaction_id", "line_no", "store_id", "sku", "qty", "unit_price", "discount",
              "loyalty_id", "sold_at", "promo_code", "tender_type"]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def rng_for(*parts: object) -> random.Random:
    """A random generator that depends only on its inputs: deterministic across runs."""
    return random.Random("|".join(str(p) for p in (SEED, *parts)))


def int_seed(*parts: object) -> int:
    return int(hashlib.md5("|".join(str(p) for p in (SEED, *parts)).encode()).hexdigest()[:8], 16)


def ts(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def short_hash(value: str, n: int = 10) -> str:
    return hashlib.md5(value.encode()).hexdigest()[:n]


def weighted(rng: random.Random, spec: tuple[list, list]):
    return rng.choices(spec[0], weights=spec[1])[0]


# ---------------------------------------------------------------------------
# The simulated world
# ---------------------------------------------------------------------------
class RetailWorld:
    """Master data (stores, products, customers) that evolves day by day."""

    def __init__(self, start: date, forced_changes: list[dict]):
        self.start = start
        self.forced: dict[str, list[dict]] = {}
        for fc in forced_changes:
            self.forced.setdefault(fc["date"], []).append(fc)

        rng = rng_for("masters")
        self.fake = Faker()
        self.fake.seed_instance(int_seed("masters"))
        self.stores = self._build_stores(rng)
        self.products: dict[str, dict] = self._build_products(rng)
        self.product_list = list(self.products.values())
        self.customers: dict[str, dict] = {}
        self.next_customer = 1
        history_start = datetime.combine(start - timedelta(days=3 * 365), time(9))
        for _ in range(N_CUSTOMERS):
            created = history_start + timedelta(minutes=rng.randint(0, 3 * 365 * 24 * 60 - 1))
            self._new_customer(rng, created)
        self.guests = [f"guest{n:05d}@example.net" for n in range(1, N_GUESTS + 1)]
        self.changed_customers: list[dict] = []
        self.changed_products: list[dict] = []

    # --- master data builders ------------------------------------------------
    @staticmethod
    def _build_stores(rng: random.Random) -> list[dict]:
        stores = []
        for i in range(1, N_STORES_KE + N_STORES_QA + 1):
            country = "KE" if i <= N_STORES_KE else "QA"
            city = (KE_CITIES if country == "KE" else QA_CITIES)[(i - 1) % (5 if country == "KE" else 4)]
            stores.append({
                "store_id": f"S{i:03d}",
                "store_name": f"RetailOne {city} {i:02d}",
                "city": city,
                "country_code": country,
                "region": country,
                "opened_date": (date(2015, 1, 1) + timedelta(days=rng.randint(0, 3000))).isoformat(),
                "size_sqm": rng.choice([800, 1200, 1500, 2000, 3500]),
            })
        return stores

    @staticmethod
    def _build_products(rng: random.Random) -> dict[str, dict]:
        products = {}
        cats = list(CATEGORIES)
        for i in range(1, N_SKUS + 1):
            category = cats[(i - 1) % len(cats)]
            subcats, (lo, hi) = CATEGORIES[category]
            subcategory = rng.choice(subcats)
            brand = rng.choice(BRANDS)
            price = round(rng.uniform(lo, hi), 2)
            products[f"SKU-{i:05d}"] = {
                "sku": f"SKU-{i:05d}",
                "product_name": f"{brand} {subcategory} {rng.choice(['Classic', 'Plus', 'Max', 'Lite', 'Pro'])} {i}",
                "category": category,
                "subcategory": subcategory,
                "brand": brand,
                "unit_cost": round(price * rng.uniform(0.55, 0.8), 2),
                "list_price": price,
                "updated_at": "2023-01-01 00:00:00",
            }
        return products

    def _new_customer(self, rng: random.Random, created: datetime) -> dict:
        n = self.next_customer
        self.next_customer += 1
        country = "KE" if rng.random() < 0.6 else "QA"
        first, last = self.fake.first_name(), self.fake.last_name()
        clean = lambda s: re.sub(r"[^a-z]", "", s.lower())  # noqa: E731
        member = rng.random() < 0.7
        phone = ("+2547" if country == "KE" else "+974") + "".join(str(rng.randint(0, 9)) for _ in range(8))
        customer = {
            "customer_id": f"C{n:05d}",
            "loyalty_id": f"L{n:06d}" if member else None,
            "email": f"{clean(first)}.{clean(last)}.{n}@example.com",
            "phone": phone,
            "first_name": first,
            "last_name": last,
            "birth_date": (date(1950, 1, 1) + timedelta(days=rng.randint(0, 20000))).isoformat(),
            "city": rng.choice(KE_CITIES if country == "KE" else QA_CITIES),
            "country_code": country,
            "segment": weighted(rng, SEGMENTS),
            "loyalty_tier": weighted(rng, TIERS) if member else None,
            "marketing_consent": rng.random() < 0.65,
            "created_at": ts(created),
            "updated_at": ts(created),
        }
        self.customers[customer["customer_id"]] = customer
        return customer

    # --- daily evolution -------------------------------------------------------
    def advance(self, d: date) -> None:
        """Apply the changes that happen on day d (before stores open)."""
        self.changed_customers, self.changed_products = [], []
        if d == self.start:  # day 1 = full extract of everything
            self.changed_customers = [dict(c) for c in self.customers.values()]
            self.changed_products = [dict(p) for p in self.products.values()]
            return

        rng = rng_for("mutate", d)
        self.fake.seed_instance(int_seed("mutate", d))
        base = datetime.combine(d, time(1, 0))

        # ~0.3% of customers change something (tier, city, segment, consent)
        for cid in rng.sample(list(self.customers), k=max(1, len(self.customers) * 3 // 1000)):
            c = self.customers[cid]
            change = rng.choice(["tier", "tier", "city", "segment", "consent"])
            if change == "tier":
                if c["loyalty_id"] is None:  # enrol into the loyalty programme
                    c["loyalty_id"] = f"L{int(cid[1:]):06d}"
                    c["loyalty_tier"] = "BRONZE"
                else:
                    tiers = TIERS[0]
                    idx = tiers.index(c["loyalty_tier"])
                    c["loyalty_tier"] = tiers[max(0, min(len(tiers) - 1, idx + rng.choice([-1, 1, 1])))]
            elif change == "city":
                c["city"] = rng.choice(KE_CITIES if c["country_code"] == "KE" else QA_CITIES)
            elif change == "segment":
                c["segment"] = weighted(rng, SEGMENTS)
            else:
                c["marketing_consent"] = not c["marketing_consent"]
            c["updated_at"] = ts(base + timedelta(minutes=rng.randint(0, 240)))
            self.changed_customers.append(dict(c))

        # new sign-ups
        for _ in range(rng.randint(5, 15)):
            c = self._new_customer(rng, base + timedelta(minutes=rng.randint(0, 240)))
            self.changed_customers.append(dict(c))

        # changes forced from the command line (acceptance test 3)
        for fc in self.forced.get(d.isoformat(), []):
            c = self.customers.get(fc["customer_id"])
            if c is None:
                print(f"WARNING: forced change for unknown customer {fc['customer_id']} ignored")
                continue
            if c["loyalty_id"] is None:
                c["loyalty_id"] = f"L{int(c['customer_id'][1:]):06d}"
            c["loyalty_tier"] = fc["loyalty_tier"]
            c["updated_at"] = ts(base + timedelta(hours=4, minutes=59))
            self.changed_customers.append(dict(c))

        # a few price changes
        for sku in rng.sample(list(self.products), k=rng.randint(3, 8)):
            p = self.products[sku]
            p["list_price"] = round(p["list_price"] * rng.uniform(0.9, 1.15), 2)
            p["unit_cost"] = round(min(p["unit_cost"], p["list_price"] * 0.9), 2)
            p["updated_at"] = ts(base + timedelta(minutes=rng.randint(0, 240)))
            self.changed_products.append(dict(p))

    # --- daily facts -------------------------------------------------------------
    def pos_sales(self, d: date) -> dict[str, list[list]]:
        members = {"KE": [], "QA": []}
        for c in self.customers.values():
            if c["loyalty_id"]:
                members[c["country_code"]].append(c)
        weekend = d.weekday() >= 4  # Fri, Sat, Sun are busier
        out: dict[str, list[list]] = {}
        for s in self.stores:
            rng = rng_for("pos", d, s["store_id"])
            n_txn = int(rng.randint(90, 160) * (1.3 if weekend else 1.0))
            rows: list[list] = []
            for t in range(1, n_txn + 1):
                sold_at = datetime.combine(d, time(8)) + timedelta(seconds=rng.randint(0, 13 * 3600))
                is_return = rng.random() < 0.02
                local = members[s["country_code"]]
                cust = rng.choice(local) if (local and rng.random() < 0.55) else None
                promo = rng.choice(list(PROMOS)) if rng.random() < 0.15 else None
                tender = rng.choice(TENDERS[s["country_code"]])
                txn_id = f"{'R' if is_return else 'T'}-{s['store_id']}-{d:%Y%m%d}-{t:05d}"
                for line_no in range(1, rng.choices([1, 2, 3, 4, 5], weights=[35, 30, 18, 10, 7])[0] + 1):
                    p = rng.choice(self.product_list)
                    qty = rng.choice([1, 1, 1, 2, 2, 3]) * (-1 if is_return else 1)
                    price = p["list_price"]
                    discount = round(qty * price * PROMOS[promo], 2) if promo else 0.0
                    rows.append([txn_id, line_no, s["store_id"], p["sku"], qty, f"{price:.2f}", f"{discount:.2f}",
                                 cust["loyalty_id"] if cust else "", ts(sold_at + timedelta(seconds=line_no)),
                                 promo or "", tender])
            out[s["store_id"]] = rows
        return out

    @staticmethod
    def pos_control(d: date, sales: dict[str, list[list]]) -> list[list]:
        rows = []
        for store_id, lines in sales.items():
            gross = sum(r[4] * float(r[5]) for r in lines)
            disc = sum(float(r[6]) for r in lines)
            rows.append([d.isoformat(), store_id, len({r[0] for r in lines}), len(lines),
                         f"{gross:.2f}", f"{disc:.2f}", f"{gross - disc:.2f}"])
        return rows

    def orders_and_events(self, d: date) -> tuple[list[dict], list[dict]]:
        rng = rng_for("orders", d)
        crm = list(self.customers.values())
        has_delivery_method = (d - self.start).days >= SCHEMA_CHANGE_AFTER_DAYS
        orders, events = [], []
        for o in range(1, rng.randint(250, 400) + 1):
            if rng.random() < 0.8:
                c = rng.choice(crm)
                email, city, country = c["email"], c["city"], c["country_code"]
            else:
                email = rng.choice(self.guests)
                country = rng.choice(["KE", "QA"])
                city = rng.choice(KE_CITIES if country == "KE" else QA_CITIES)
            order_id = f"O-{d:%Y%m%d}-{o:05d}"
            ordered_at = datetime.combine(d, time(0)) + timedelta(seconds=rng.randint(0, 86399))
            status = weighted(rng, ORDER_STATUS)
            delivery = rng.choice(DELIVERY_METHODS)
            anon = "A" + short_hash(email + str(rng.randint(0, 3)))
            for line in range(1, rng.choices([1, 2, 3, 4], weights=[45, 30, 15, 10])[0] + 1):
                p = rng.choice(self.product_list)
                qty = rng.choice([1, 1, 2, 3])
                promo_pct = rng.choice([0, 0, 0, 0.1, 0.15])
                row = {
                    "order_id": order_id, "order_line": line,
                    "web_customer_id": "W" + short_hash(email), "customer_email": email,
                    "sku": p["sku"], "qty": qty, "unit_price": p["list_price"],
                    "discount": round(qty * p["list_price"] * promo_pct, 2),
                    "ordered_at": ordered_at, "order_status": status,
                    "ship_city": city, "ship_country": country,
                }
                if has_delivery_method:
                    row["delivery_method"] = delivery
                orders.append(row)

            # marketing touches that led to this order (attribution input)
            if rng.random() < 0.75:
                for j in range(rng.choices([1, 2, 3, 4], weights=[40, 30, 20, 10])[0]):
                    channel = weighted(rng, CHANNELS)
                    touched_at = ordered_at - timedelta(minutes=rng.randint(5, 72 * 60))
                    source, medium, campaign, etype = None, "none", None, "page_view"
                    if channel == "paid_search":
                        source, medium, etype = "google", "cpc", "ad_click"
                        campaign = rng.choice(CAMPAIGNS["google"])[0]
                    elif channel == "paid_social":
                        source, medium, etype = "meta", "paid_social", "ad_click"
                        campaign = rng.choice(CAMPAIGNS["meta"])[0]
                    elif channel == "email":
                        source, medium, etype = "newsletter", "email", "email_open"
                        campaign = f"EMAIL-{touched_at:%Y-%W}"
                    elif channel == "organic":
                        source, medium = "google", "organic"
                    events.append({
                        "event_id": f"E-{order_id}-{j}", "event_ts": ts(touched_at), "event_type": etype,
                        "anonymous_id": anon, "customer_email": email, "channel": channel,
                        "utm_source": source, "utm_medium": medium, "utm_campaign": campaign,
                        "page": rng.choice(["/", "/deals", "/c/grocery", "/c/electronics", "/c/apparel"]),
                        "order_id": None,
                    })
            events.append({
                "event_id": f"E-{order_id}-P", "event_ts": ts(ordered_at), "event_type": "purchase",
                "anonymous_id": anon, "customer_email": email, "channel": None,
                "utm_source": None, "utm_medium": None, "utm_campaign": None,
                "page": "/checkout/complete", "order_id": order_id,
            })

        # anonymous browsing noise
        for k in range(rng.randint(1500, 2500)):
            channel = weighted(rng, CHANNELS)
            events.append({
                "event_id": f"E-{d:%Y%m%d}-N{k:05d}",
                "event_ts": ts(datetime.combine(d, time(0)) + timedelta(seconds=rng.randint(0, 86399))),
                "event_type": "page_view", "anonymous_id": "A" + short_hash(f"{d}{k}"),
                "customer_email": None, "channel": channel,
                "utm_source": {"paid_search": "google", "paid_social": "meta"}.get(channel),
                "utm_medium": {"paid_search": "cpc", "paid_social": "paid_social", "email": "email"}.get(channel, "none"),
                "utm_campaign": None, "page": rng.choice(["/", "/deals", "/c/grocery", "/search"]), "order_id": None,
            })
        return orders, events

    @staticmethod
    def ads(d: date) -> dict[str, list[dict]]:
        """Same deterministic mock as the Cloud Run job (gcp/g3_cloud_run_ads/main.py)."""
        out = {}
        for platform, campaigns in CAMPAIGNS.items():
            rng = random.Random(f"ads|{platform}|{d.isoformat()}")
            rows = []
            for campaign_id, campaign_name in campaigns:
                for ad_no in (1, 2):
                    spend = round(rng.uniform(40, 400), 2)
                    impressions = int(spend * rng.uniform(80, 220))
                    clicks = int(impressions * rng.uniform(0.008, 0.04))
                    rows.append({
                        "date": d.isoformat(), "platform": platform,
                        "campaign_id": campaign_id, "campaign_name": campaign_name,
                        "ad_id": f"{campaign_id}-AD{ad_no}", "ad_name": f"{campaign_name} - Variant {ad_no}",
                        "spend": spend, "currency": "USD", "impressions": impressions, "clicks": clicks,
                        "conversions": int(clicks * rng.uniform(0.01, 0.06)),
                    })
            out[platform] = rows
        return out

    def inventory(self, d: date) -> list[list]:
        rows = []
        for s in self.stores:
            rng = rng_for("inventory", d, s["store_id"])
            for p in self.product_list:
                rows.append([d.isoformat(), s["store_id"], p["sku"], rng.randint(0, 150)])
        return rows

    def reviews(self, d: date) -> list[dict]:
        rng = rng_for("reviews", d)
        crm = list(self.customers.values())
        rows = []
        for k in range(1, rng.randint(30, 60) + 1):
            p = rng.choice(self.product_list)
            rating = rng.choices([5, 4, 3, 2, 1], weights=[40, 30, 12, 8, 10])[0]
            short_name = f"{p['subcategory'].lower()} from {p['brand']}"
            rows.append({
                "review_id": f"RV-{d:%Y%m%d}-{k:04d}", "sku": p["sku"],
                "customer_id": rng.choice(crm)["customer_id"], "rating": rating,
                "review_text": rng.choice(REVIEW_TEMPLATES[rating]).format(p=short_name),
                "created_at": ts(datetime.combine(d, time(0)) + timedelta(seconds=rng.randint(0, 86399))),
            })
        return rows


# ---------------------------------------------------------------------------
# Writers
# ---------------------------------------------------------------------------
class Writer:
    def __init__(self, output_dir: Path):
        self.root = output_dir
        self.written: list[Path] = []

    def _path(self, source: str, d: date, filename: str, held: bool = False) -> Path:
        base = self.root / "_held" if held else self.root
        path = base / source / f"dt={d.isoformat()}" / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def csv(self, source: str, d: date, filename: str, header: list[str], rows: list[list], held=False) -> Path:
        path = self._path(source, d, filename, held)
        with path.open("w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(header)
            w.writerows(["" if v is None else v for v in r] for r in rows)
        if not held:
            self.written.append(path)
        return path

    def ndjson(self, source: str, d: date, filename: str, rows: list[dict]) -> Path:
        path = self._path(source, d, filename)
        with path.open("w", encoding="utf-8") as fh:
            for r in rows:
                fh.write(json.dumps(r, default=str) + "\n")
        self.written.append(path)
        return path

    def parquet(self, source: str, d: date, filename: str, rows: list[dict]) -> Path:
        path = self._path(source, d, filename)
        df = pd.DataFrame(rows)
        df.to_parquet(path, engine="pyarrow", index=False,
                      coerce_timestamps="ms", allow_truncated_timestamps=True)
        self.written.append(path)
        return path


def generate_day(world: RetailWorld, d: date, w: Writer, chaos: dict, run_id: str) -> None:
    world.advance(d)

    sales = world.pos_sales(d)
    for store_id, rows in sales.items():
        held = chaos.get("late_store") == store_id
        w.csv("pos_sales", d, f"store_{store_id}.csv", POS_HEADER, rows, held=held)
        if held:
            print(f"   chaos: holding back {store_id} for {d} (it will arrive LATE with the next run)")
    w.csv("pos_control", d, "control_totals.csv",
          ["business_date", "store_id", "txn_count", "line_count", "gross_amount", "discount_amount", "net_amount"],
          world.pos_control(d, sales))

    if chaos.get("duplicate_file"):
        first = world.stores[0]["store_id"]
        w.csv("pos_sales", d, f"store_{first}_resend.csv", POS_HEADER, sales[first])
        print(f"   chaos: re-sent store {first} file as store_{first}_resend.csv (duplicates)")
    if chaos.get("bad_file"):
        w.csv("pos_sales", d, "store_S999_corrupt.csv", POS_HEADER, [
            [f"T-S999-{d:%Y%m%d}-00001", 1, "S999", "SKU-00001", "abc", "9.99", "0.00", "", "not-a-date", "", "CARD"],
            [f"T-S999-{d:%Y%m%d}-00001", 2, "S999", "SKU-00002", "1", "oops", "0.00", "", "2026-13-45 99:00:00", "", "CARD"],
        ])
        print("   chaos: wrote corrupt file store_S999_corrupt.csv (should be SKIPPED by COPY/Snowpipe)")

    orders, events = world.orders_and_events(d)
    w.parquet("ecom_orders", d, "orders.parquet", orders)
    w.ndjson("web_events", d, "events.json", events)

    w.ndjson("crm_customers", d, "customers.json", world.changed_customers)
    w.csv("erp_products", d, "products.csv",
          ["sku", "product_name", "category", "subcategory", "brand", "unit_cost", "list_price", "updated_at"],
          [[p[k] for k in ["sku", "product_name", "category", "subcategory", "brand", "unit_cost", "list_price", "updated_at"]]
           for p in world.changed_products])
    if d == world.start:
        w.csv("erp_stores", d, "stores.csv",
              ["store_id", "store_name", "city", "country_code", "region", "opened_date", "size_sqm", "updated_at"],
              [[s[k] for k in ["store_id", "store_name", "city", "country_code", "region", "opened_date", "size_sqm"]]
               + [ts(datetime.combine(d, time(0)))] for s in world.stores])
    w.csv("erp_inventory", d, "inventory.csv", ["snapshot_date", "store_id", "sku", "opening_qty"], world.inventory(d))

    for platform, rows in world.ads(d).items():
        w.ndjson("ads", d, f"ads_{platform}_{run_id}.json", rows)
    w.ndjson("reviews", d, "reviews.json", world.reviews(d))


# ---------------------------------------------------------------------------
# State, upload, CLI
# ---------------------------------------------------------------------------
def load_state(output_dir: Path) -> dict:
    path = output_dir / "_state.json"
    return json.loads(path.read_text()) if path.exists() else {}


def save_state(output_dir: Path, state: dict) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "_state.json").write_text(json.dumps(state, indent=2))


def release_held_files(output_dir: Path, w: Writer) -> None:
    held_root = output_dir / "_held"
    if not held_root.exists():
        return
    for path in sorted(held_root.rglob("*.*")):
        target = output_dir / path.relative_to(held_root)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(path), target)
        w.written.append(target)
        print(f"   late file arrives now: {target.relative_to(output_dir).as_posix()}")
    shutil.rmtree(held_root, ignore_errors=True)


def upload(files: list[Path], output_dir: Path) -> None:
    from google.cloud import storage

    bucket_name = os.getenv("GCS_LANDING_BUCKET")
    if not bucket_name or "YOUR_PROJECT_ID" in bucket_name:
        sys.exit("GCS_LANDING_BUCKET is not set (load your .env first)")
    bucket = storage.Client(project=os.getenv("GCP_PROJECT_ID")).bucket(bucket_name)

    def _one(path: Path) -> str:
        name = path.relative_to(output_dir).as_posix()
        bucket.blob(name).upload_from_filename(str(path))
        return name

    print(f">> uploading {len(files)} files to gs://{bucket_name}/")
    with ThreadPoolExecutor(max_workers=16) as pool:
        for i, _ in enumerate(pool.map(_one, files), start=1):
            if i % 100 == 0 or i == len(files):
                print(f"   {i}/{len(files)}")


def run_days(days: list[date], state: dict, args: argparse.Namespace) -> None:
    output_dir = Path(args.output_dir)
    world = RetailWorld(date.fromisoformat(state["start_date"]), state.get("forced_changes", []))
    w = Writer(output_dir)
    release_held_files(output_dir, w)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    # Replay master-data history silently up to the first requested day (keeps the world consistent).
    d = world.start
    while d < days[0]:
        world.advance(d)
        d += timedelta(days=1)

    for i, d in enumerate(days):
        is_last = i == len(days) - 1
        chaos = {
            "late_store": args.late_store if is_last else None,
            "bad_file": args.inject_bad_file and is_last,
            "duplicate_file": args.duplicate_file and is_last,
        }
        generate_day(world, d, w, chaos, run_id)
        if (i + 1) % 10 == 0 or is_last:
            print(f"   generated {d} ({i + 1}/{len(days)})")

    state["last_date"] = days[-1].isoformat()
    save_state(output_dir, state)
    print(f">> wrote {len(w.written)} files under {output_dir.resolve()}")
    if args.upload:
        upload(w.written, output_dir)


def main() -> None:
    load_dotenv(find_dotenv(usecwd=True))
    default_out = Path(__file__).resolve().parent / "output"

    parser = argparse.ArgumentParser(description="RetailOne synthetic data generator")
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--output-dir", default=str(default_out), help="local output folder")
    common.add_argument("--upload", action="store_true", help="upload the new files to GCS_LANDING_BUCKET")
    common.add_argument("--late-store", help="hold back this store's POS file for the last day (e.g. S007)")
    common.add_argument("--inject-bad-file", action="store_true", help="add a corrupt POS file on the last day")
    common.add_argument("--duplicate-file", action="store_true", help="re-send one store file on the last day")
    sub = parser.add_subparsers(dest="command", required=True)

    p_back = sub.add_parser("backfill", parents=[common], help="generate N days of history")
    p_back.add_argument("--days", type=int, default=90)
    p_back.add_argument("--end-date", default=(date.today() - timedelta(days=1)).isoformat(),
                        help="last day to generate (default: yesterday)")

    sub.add_parser("new-day", parents=[common], help="generate the next day after the last generated one")

    p_tier = sub.add_parser("change-tier", parents=[common], help="force a loyalty tier change on the next day")
    p_tier.add_argument("--customer-id", required=True)
    p_tier.add_argument("--tier", required=True, choices=TIERS[0])

    sub.add_parser("status", parents=[common], help="show generator state")

    args = parser.parse_args()
    output_dir = Path(args.output_dir)
    state = load_state(output_dir)

    if args.command == "backfill":
        end = date.fromisoformat(args.end_date)
        start = end - timedelta(days=args.days - 1)
        state = {"start_date": start.isoformat(), "forced_changes": state.get("forced_changes", [])}
        print(f">> backfill {start} -> {end} ({args.days} days)")
        run_days([start + timedelta(days=i) for i in range(args.days)], state, args)

    elif args.command == "new-day":
        if not state.get("last_date"):
            sys.exit("No state found. Run `backfill` first.")
        nxt = date.fromisoformat(state["last_date"]) + timedelta(days=1)
        print(f">> new day {nxt}")
        run_days([nxt], state, args)

    elif args.command == "change-tier":
        if not state.get("last_date"):
            sys.exit("No state found. Run `backfill` first.")
        nxt = (date.fromisoformat(state["last_date"]) + timedelta(days=1)).isoformat()
        state.setdefault("forced_changes", []).append(
            {"date": nxt, "customer_id": args.customer_id, "loyalty_tier": args.tier})
        save_state(output_dir, state)
        print(f">> {args.customer_id} will become {args.tier} on {nxt}. Run `new-day --upload` to send it.")

    elif args.command == "status":
        print(json.dumps(state, indent=2) if state else "No state yet. Run `backfill` first.")
        held = output_dir / "_held"
        if held.exists():
            print("Held (late) files:", [p.relative_to(held).as_posix() for p in held.rglob("*.*")])


if __name__ == "__main__":
    main()
