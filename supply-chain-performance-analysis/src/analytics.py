"""
analytics.py
------------
Computes the headline business metrics and the ABC inventory classification
from the cleaned supply chain data, and writes a machine-readable summary so
that every figure quoted in the README is reproducible.

Run:
    python src/analytics.py
Output:
    outputs/kpi_summary.json
    outputs/abc_classification.csv
    outputs/warehouse_performance.csv
"""
from __future__ import annotations

import json
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
CLEAN_PATH = ROOT / "data" / "Cleaned_Supplychain_Data.csv"
OUT_DIR = ROOT / "outputs"


def load() -> pd.DataFrame:
    return pd.read_csv(CLEAN_PATH)


def kpis(df: pd.DataFrame) -> dict:
    total_rev = df["revenue"].sum()
    total_profit = df["profit"].sum()
    return {
        "orders": int(len(df)),
        "total_revenue": round(float(total_rev), 2),
        "total_profit": round(float(total_profit), 2),
        "avg_profit_margin_pct": round(float(df["profit_margin"].mean() * 100), 1),
        "avg_delivery_days": round(float(df["delivery_days"].mean()), 1),
        "min_delivery_days": int(df["delivery_days"].min()),
        "max_delivery_days": int(df["delivery_days"].max()),
        "on_time_rate_pct": round(float(df["on_time"].mean() * 100), 1),
        "late_orders": int((~df["on_time"].astype(bool)).sum()),
        "unprofitable_orders": int((df["profit"] < 0).sum()),
        "unprofitable_pct": round(float((df["profit"] < 0).mean() * 100), 2),
    }


def abc_classification(df: pd.DataFrame) -> pd.DataFrame:
    """Segment products by cumulative revenue contribution (Pareto)."""
    prod = (
        df.groupby("_ProductID")["revenue"].sum().sort_values(ascending=False).reset_index()
    )
    prod["cum_pct"] = prod["revenue"].cumsum() / prod["revenue"].sum() * 100

    def bucket(cum: float) -> str:
        if cum <= 80:
            return "A"
        if cum <= 95:
            return "B"
        return "C"

    prod["class"] = prod["cum_pct"].apply(bucket)
    return prod


def abc_summary(prod: pd.DataFrame) -> dict:
    total_rev = prod["revenue"].sum()
    out = {}
    for cls in ["A", "B", "C"]:
        sub = prod[prod["class"] == cls]
        out[cls] = {
            "products": int(len(sub)),
            "product_share_pct": round(len(sub) / len(prod) * 100, 1),
            "revenue_share_pct": round(sub["revenue"].sum() / total_rev * 100, 1),
        }
    return out


def warehouse_performance(df: pd.DataFrame) -> pd.DataFrame:
    g = (
        df.groupby("WarehouseCode")
        .agg(
            orders=("OrderNumber", "count"),
            avg_delivery_days=("delivery_days", "mean"),
            on_time_rate_pct=("on_time", lambda s: s.mean() * 100),
            revenue=("revenue", "sum"),
        )
        .round(2)
        .sort_values("avg_delivery_days")
    )
    late = df[~df["on_time"].astype(bool)]
    late_share = (late.groupby("WarehouseCode").size() / len(late) * 100).round(1)
    g["share_of_late_pct"] = late_share
    return g.reset_index()


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    df = load()

    k = kpis(df)
    prod = abc_classification(df)
    k["abc"] = abc_summary(prod)
    wh = warehouse_performance(df)

    # Identify best / worst hubs for the narrative.
    best = wh.iloc[0]
    worst = wh.sort_values("avg_delivery_days").iloc[-1]
    k["best_warehouse"] = {
        "code": best["WarehouseCode"],
        "avg_delivery_days": float(best["avg_delivery_days"]),
        "on_time_rate_pct": round(float(best["on_time_rate_pct"]), 1),
    }
    k["worst_warehouse"] = {
        "code": worst["WarehouseCode"],
        "avg_delivery_days": float(worst["avg_delivery_days"]),
        "share_of_late_pct": float(worst.get("share_of_late_pct", 0) or 0),
    }

    (OUT_DIR / "kpi_summary.json").write_text(json.dumps(k, indent=2))
    prod.to_csv(OUT_DIR / "abc_classification.csv", index=False)
    wh.to_csv(OUT_DIR / "warehouse_performance.csv", index=False)

    print(json.dumps(k, indent=2))


if __name__ == "__main__":
    main()
