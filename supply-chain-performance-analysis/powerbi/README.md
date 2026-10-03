# 📊 Power BI Dashboard — Supply Chain Performance

This folder holds the Power BI assets for the supply chain project. The model is
built directly on `data/Cleaned_Supplychain_Data.csv` (produced by
`src/data_cleaning.py`).

## How to build it

1. **Get Data → Text/CSV** → select `data/Cleaned_Supplychain_Data.csv`.
2. Confirm types: dates as *Date*, `revenue`/`profit`/`unit_*` as *Decimal*.
3. Create the measures below (Modeling → New measure).
4. Build the report pages described in the layout section.

## DAX measures

```dax
Total Revenue   = SUM ( Supplychain[revenue] )
Total Profit    = SUM ( Supplychain[profit] )
Profit Margin % = DIVIDE ( [Total Profit], [Total Revenue] )
Order Count     = COUNTROWS ( Supplychain )
Avg Delivery Days = AVERAGE ( Supplychain[delivery_days] )
On-Time Rate %  =
    DIVIDE (
        CALCULATE ( [Order Count], Supplychain[on_time] = TRUE () ),
        [Order Count]
    )
Late Orders     = CALCULATE ( [Order Count], Supplychain[on_time] = FALSE () )
```

## Suggested report layout

| Page | Visuals |
| :--- | :--- |
| **Executive Overview** | KPI cards (Revenue, Profit, Margin %, On-Time %), revenue by Sales Channel (donut), monthly revenue trend (line) |
| **Fulfillment** | Avg delivery days by warehouse (bar), on-time vs late (stacked), delivery-days distribution (histogram) |
| **Profitability** | Profit by channel (bar), margin by product (scatter), top products table |

> A rendered screenshot of the report should be exported to
> `../image/` once built. The interactive `.pbix` belongs in this folder.
