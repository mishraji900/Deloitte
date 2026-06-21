# GL Diverging Bar + Polygon Sankey — Data Prep & Tableau Build Guide

## 0. Schema assumed coming out of the GL/COA join

| Column            | Notes                                   |
|-------------------|------------------------------------------|
| Entity            | filter                                    |
| LOB               | filter                                    |
| Grouping          | filter                                    |
| FS Line           | filter (also a Y-axis option on the bar) |
| FS Category       | sankey center pillar                      |
| Account           | bar Y-axis option                         |
| Acct Desc         | bar Y-axis option                         |
| Account Grp       | descriptive                               |
| Transaction Type  | bar Y-axis option                         |
| Flag              | A,B,C,D,E,Other — sankey left/right pillar|
| Balance            | + = debit, - = credit                    |

---

## 1. Diverging Bar Chart — no row explosion needed

This stays at the **aggregated grain**, so it's safe at any volume (10M → a few thousand rows).

```python
from pyspark.sql import functions as F

def prep_diverging_bar(df_gl):
    dims = ["Entity", "LOB", "Grouping", "FS Line", "FS Category",
            "Account", "Acct Desc", "Transaction Type"]

    df_bar = (
        df_gl.groupBy(*dims)
             .agg(
                 F.sum("Balance").alias("Net_Balance"),
                 F.sum(F.when(F.col("Balance") > 0, F.col("Balance")).otherwise(0))
                  .alias("Debit_Balance"),
                 F.sum(F.when(F.col("Balance") < 0, F.col("Balance")).otherwise(0))
                  .alias("Credit_Balance"),
                 F.count("*").alias("Txn_Count")
             )
    )
    return df_bar
```

**In Tableau:**
- Parameter `Pivot Dimension` (string list): FS Line / FS Category / Acct Desc / Account / Transaction Type
- Calc `Pivot Value`:
```
CASE [Pivot Dimension]
WHEN "FS Line" THEN [FS Line]
WHEN "FS Category" THEN [FS Category]
WHEN "Acct Desc" THEN [Acct Desc]
WHEN "Account" THEN [Account]
WHEN "Transaction Type" THEN [Transaction Type]
END
```
- Rows: `Pivot Value` (sorted by SUM(Net_Balance))
- Columns: `SUM(Net_Balance)`
- Color: `SUM(Net_Balance)` sign (diverging palette, center at 0)
- No issue with this sheet at 10M source rows — it's a pre-aggregated extract.

---

## 2. Sankey — Step 1: collapse transactions to LINK grain

This is the fix for both the "sankey doesn't form" problem and the scale problem. A ribbon represents one **link total**, not a transaction, so aggregate first.

```python
def prep_sankey_links(df_gl):
    df_flow = (
        df_gl
        .withColumn("Flow_Type",
                    F.when(F.col("Balance") > 0, F.lit("Debit"))
                     .otherwise(F.lit("Credit")))
        .withColumn("Link_Value", F.abs(F.col("Balance")))
    )

    # keep every filter dimension you need interactivity on
    link_dims = ["Entity", "LOB", "Grouping", "FS Line",
                 "Flag", "FS Category", "Flow_Type"]

    df_links = (
        df_flow.groupBy(*link_dims)
               .agg(F.sum("Link_Value").alias("Link_Value"))
               .withColumn("Source",
                   F.when(F.col("Flow_Type") == "Debit", F.col("Flag"))
                    .otherwise(F.col("FS Category")))
               .withColumn("Target",
                   F.when(F.col("Flow_Type") == "Debit", F.col("FS Category"))
                    .otherwise(F.col("Flag")))
               .withColumn("Source_Level",
                   F.when(F.col("Flow_Type") == "Debit", F.lit(0))   # left pillar
                    .otherwise(F.lit(1)))                            # center pillar
               .withColumn("Target_Level",
                   F.when(F.col("Flow_Type") == "Debit", F.lit(1))   # center pillar
                    .otherwise(F.lit(2)))                            # right pillar
               .withColumn("Path_ID", F.monotonically_increasing_id())
               # fixed sort keys so left/right pillar order is stable & consistent
               # regardless of filters — needed for the Tableau running-sum calcs
               .withColumn("Flag_Sort",
                   F.when(F.col("Flag") == "A", 1)
                    .when(F.col("Flag") == "B", 2)
                    .when(F.col("Flag") == "C", 3)
                    .when(F.col("Flag") == "D", 4)
                    .when(F.col("Flag") == "E", 5)
                    .otherwise(6))
    )
    return df_links
```

This typically turns 10M transactions into low thousands of link rows (Entity × LOB × Grouping × FS Line × 6 flags × N FS Categories × 2 flow types).

---

## 3. Sankey — Step 2: densify the LINK table (not the transactions) into curve points

```python
def densify_for_polygon_sankey(spark, df_links, n_points=30):
    """
    n_points = curve smoothness. 20-40 is visually smooth and keeps the
    output table small: link_rows * n_points * 2 (top+bottom), e.g.
    5,000 links * 30 * 2 = 300,000 rows -> trivial for Tableau.
    """
    t_values = [round(i / (n_points - 1), 5) for i in range(n_points)]
    df_t = spark.createDataFrame([(t,) for t in t_values], ["T"])

    df_dense = df_links.crossJoin(df_t)

    # Pre-bake the sigmoid shape here (data-independent, safe to bake) —
    # this is what makes the ribbon S-curved instead of a straight line.
    df_dense = df_dense.withColumn(
        "Sigmoid_T",
        F.lit(1.0) / (F.lit(1.0) + F.exp(F.lit(-12.0) * (F.col("T") - F.lit(0.5))))
    )

    # X position interpolates linearly between source/target pillar (0,1,2)
    df_dense = df_dense.withColumn(
        "Curve_X",
        F.col("Source_Level") + (F.col("Target_Level") - F.col("Source_Level")) * F.col("T")
    )

    # Build Top and Bottom edges, with a Point_Order that traces a closed
    # loop: top edge left->right, then bottom edge right->left.
    df_top = (df_dense
        .withColumn("Side", F.lit("Top"))
        .withColumn("Point_Order", (F.col("T") * (n_points - 1)).cast("int")))

    df_bottom = (df_dense
        .withColumn("Side", F.lit("Bottom"))
        .withColumn("Point_Order",
            F.lit(2 * (n_points - 1)) - (F.col("T") * (n_points - 1)).cast("int")))

    df_polygon = df_top.unionByName(df_bottom)
    return df_polygon
```

**Do NOT bake the Y (vertical) position in Spark.** The vertical stacking position of each ribbon depends on the *current filtered mix* of links sharing a node (Entity/LOB/FS Line filters change which links exist and their relative size). If you hardcode Y in Spark, the picture breaks the moment someone filters. Y is computed live in Tableau with table calcs (next section) — that's exactly what the Flerlage template does, and it's why I'd still recommend building on that template rather than from scratch: the addressing/partitioning of these table calcs has to match your worksheet's pill order exactly, and that's fragile to hand-roll blind.

Output of this stage — load this single table as the Sankey data source:

| Path_ID | Side | Point_Order | T | Sigmoid_T | Curve_X | Link_Value | Source | Target | Flag | Flag_Sort | FS Category | Flow_Type | Entity | LOB | Grouping | FS Line |

---

## 4. Tableau calculated fields (map onto the template / build manually)

**Sigmoid (normalized 0→1):**
```
([Sigmoid_T] - 1/(1+EXP(6))) / (1/(1+EXP(-6)) - 1/(1+EXP(6)))
```

**Node running total (bottom of stack) — table calc, partitioned by node, sorted by Flag_Sort / FS Category sort:**
```
// "Y Start Bottom" — drag Source (or Target) into the partition,
// addressing = Path, compute using Flag_Sort then Path_ID as tiebreaker
WINDOW_SUM(SUM([Link_Value])) - SUM([Link_Value])
```

**Y Start Top:**
```
[Y Start Bottom] + SUM([Link_Value])
```
(Do the same pattern partitioned by Target node for Y End Bottom / Y End Top.)

**Curve Y (the actual band edge at each point):**
```
IF [Side] = "Top"
THEN [Y Start Top] + ([Y End Top] - [Y Start Top]) * [Sigmoid]
ELSE [Y Start Bottom] + ([Y End Bottom] - [Y Start Bottom]) * [Sigmoid]
END
```

**Mark setup:**
- Mark type: **Polygon**
- Path: `Path_ID` (one polygon per link)
- Order points by: `Side`, then `Point_Order`
- X: `Curve_X`, Y: `Curve Y`
- Color: `Flag` or `Flow_Type`
- Size of ribbon comes naturally from the gap between Top/Bottom Y, driven by `Link_Value`

---

## 5. Linking the two pillars + bar chart in one dashboard (the "click A → highlight both paths" behavior)

- Add `Flag` as a dashboard **filter action** AND a **highlight action** (use highlight, not filter, so both ribbons touching Flag A stay visible, just dimmed elsewhere).
- Source: any sheet with `Flag` (left pillar marks, or a small Flag legend sheet)
- Target: the Sankey polygon sheet — Tableau will highlight every Path_ID where `Flag` = the clicked value, which naturally includes *both* the Debit ribbon (Flag→FS Category) and the Credit ribbon (FS Category→Flag) since both rows carry the same `Flag` value in the link table.
- Run on: Select. Clearing selection: Show all values.
- Same `Flag`/`FS Category` field can drive a highlight action into the diverging bar sheet if you want cross-highlighting there too.

---

## 6. Scale checklist for 10M+ rows

1. **Never densify at transaction grain.** Aggregate to link grain first (Step 2) — this is the single biggest fix, both for correctness and performance.
2. Keep `n_points` modest (20–40). Visually a sankey ribbon doesn't need more; doubling it just doubles row count for no visible gain.
3. Publish as a **Tableau Extract (Hyper)**, not a live connection to Spark/Delta — table calcs (WINDOW_SUM) on a Polygon mark are calc-heavy and live queries will be slow.
4. Materialize the Step 1 aggregation (`prep_sankey_links`) as Delta/Parquet and incrementally refresh only changed Entities/periods if this is a recurring job — no need to rescan 10M rows every run if older periods are closed.
5. Keep the bar chart extract (Step 1 of section 1) and the sankey extract (Step 3) as **two separate data sources/extracts** even though they're one dashboard — don't force them into one table, since the Sankey's row count (links × n_points × 2) is a different grain than the bar chart's. Blend or use a dashboard filter action between them rather than a single blended extract.
