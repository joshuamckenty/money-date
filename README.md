# money-date

A tiny always-on-top macOS utility that shows a table of **USD → CAD** conversions
across a set of fixed dates.

- **Rows** are dates. By default the most recent **12 month-ends**; the table shows the
  most recent **15** rows.
- **Columns** are USD amounts. The table shows the most recent **5** columns.
- **Each cell** is the column's USD amount converted to CAD using the historical
  USD→CAD rate as of that row's date (European Central Bank rates via the free
  [Frankfurter](https://www.frankfurter.app/) API — no key required).

## How it works

- **Copy a number** anywhere on your Mac → a new USD column is added automatically.
- **Copy a date** (e.g. `2025-03-31`, `03/31/2025`) → a new date row is added.
- **Click a cell** → copies that cell's CAD value (plain number, ready to paste).
- **⌃⌥⌘C** (global, configurable) → copies the CAD value for the **latest** column
  and the **topmost** (most recent) date. This copy does **not** add a new column.
  Click the shortcut field in the footer and press a new combination to rebind it
  (at least one modifier required; Escape cancels).
- **Reset dates** → back to the most recent 12 month-ends.
- **Year dropdown** → repopulate the rows with all 12 month-ends of a chosen year.

The window floats above other apps, appears on all Spaces, and **never steals focus**
(it runs as an accessory app, so there's no Dock icon — use the menu-bar `$⇄` item to
show the window or quit).

## Build & run

Requires macOS 13+ and a Swift toolchain (Xcode command-line tools).

```sh
swift run            # debug
# or
swift build -c release
.build/release/MoneyDate
```

## Notes

- ECB doesn't publish rates on weekends/holidays; the Frankfurter API returns the
  nearest available business-day rate for such dates.
- Rows, columns, and fetched rates are cached as JSON in
  `~/Library/Application Support/money-date/`.

## License

MIT — see [LICENSE](LICENSE). A side project by Joshua McKenty.
