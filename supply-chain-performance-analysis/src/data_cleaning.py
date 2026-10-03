"""
data_cleaning.py
----------------
Cleans the raw supply chain transactional log and engineers the metrics used
throughout this project (delivery cycle times, revenue, cost, profit).

Input : data/Supplychain_rawData.csv  (7,991 raw order rows)
Output: data/Cleaned_Supplychain_Data.csv

Run:
    python src/data_cleaning.py
"""
from __future__ import annotations

from pathlib import Path

import pandas as pd

# Resolve paths relative to the project root (parent of this file's folder)
ROOT = Path(__file__).resolve().parents[1]
RAW_PATH = ROOT / "data" / "Supplychain_rawData.csv"
OUT_PATH = ROOT / "data" / "Cleaned_Supplychain_Data.csv"

DATE_COLS = ["ProcuredDate", "OrderDate", "ShipDate", "DeliveryDate"]
MONEY_COLS = ["Unit_Cost", "Unit_Price"]


def _standardize_headers(df: pd.DataFrame) -> pd.DataFrame:
    """Strip whitespace and convert headers to clean snake_case-ish names."""
    df = df.copy()
    df.columns = (
        df.columns.str.strip()
        .str.replace(" ", "_", regex=False)
        .str.replace("__", "_", regex=False)
    )
    return df


def _clean_money(series: pd.Series) -> pd.Series:
    """Remove currency symbols/commas and cast to float."""
    return (
        series.astype(str)
        .str.replace(r"[$,]", "", regex=True)
        .str.strip()
        .astype(float)
    )


def load_and_clean(raw_path: Path = RAW_PATH) -> pd.DataFrame:
    df = pd.read_csv(raw_path)
    df = _standardize_headers(df)

    # Parse dates. Source uses mixed day-first formats (e.g. 31/5/18, 2/7/2018).
    for col in DATE_COLS:
        df[col] = pd.to_datetime(df[col], dayfirst=True, errors="coerce")

    # Clean currency columns.
    for col in MONEY_COLS:
        df[col] = _clean_money(df[col])

    # Drop exact duplicate orders and rows missing the dates we depend on.
    df = df.drop_duplicates()
    df = df.dropna(subset=["OrderDate", "ShipDate", "DeliveryDate"])

    # ---- Feature engineering -------------------------------------------------
    df["delivery_days"] = (df["DeliveryDate"] - df["ShipDate"]).dt.days
    df["order_to_ship_days"] = (df["ShipDate"] - df["OrderDate"]).dt.days
    df["procure_to_order_days"] = (df["OrderDate"] - df["ProcuredDate"]).dt.days

    df["revenue"] = df["Order_Quantity"] * df["Unit_Price"]
    df["total_cost"] = df["Order_Quantity"] * df["Unit_Cost"]
    df["profit"] = df["revenue"] - df["total_cost"]
    df["profit_margin"] = df["profit"] / df["revenue"]

    # On-time = delivered within the median delivery window (<= 5 days here).
    df["on_time"] = df["delivery_days"] <= 5

    df["order_year"] = df["OrderDate"].dt.year
    df["order_month"] = df["OrderDate"].dt.to_period("M").astype(str)

    return df


def main() -> None:
    df = load_and_clean()
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(OUT_PATH, index=False)
    print(f"Cleaned data written to {OUT_PATH}  ({len(df):,} rows, {df.shape[1]} cols)")


if __name__ == "__main__":
    main()
