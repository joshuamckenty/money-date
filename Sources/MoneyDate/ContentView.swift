import SwiftUI

struct ContentView: View {
    @ObservedObject var store: Store

    private var years: [Int] {
        let current = DateUtils.calendar.component(.year, from: Date())
        return Array((current - 25)...(current + 1)).reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls

            Divider()

            if store.displayedColumns.isEmpty {
                emptyState
            } else {
                ScrollView([.vertical, .horizontal]) {
                    grid
                }
            }

            footer
        }
        .padding(12)
        .frame(minWidth: 380, minHeight: 240)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button("Reset dates") { store.resetDates() }

            Picker("Year", selection: $store.selectedYear) {
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 90)
            .onChange(of: store.selectedYear) { newValue in
                store.populate(year: newValue)
            }

            Spacer()

            Text("USD → CAD")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var grid: some View {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Date")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.leading)
                ForEach(store.displayedColumns) { column in
                    headerCell(column)
                }
            }
            Divider().gridCellColumns(store.displayedColumns.count + 1)

            ForEach(store.displayedRows) { row in
                GridRow {
                    dateCell(row).gridColumnAlignment(.leading)
                    ForEach(store.displayedColumns) { column in
                        valueCell(row: row, column: column)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.45), value: store.flashCellKey)
        .animation(.easeOut(duration: 0.9), value: store.recentlyAddedColumnID)
        .animation(.easeOut(duration: 0.9), value: store.recentlyAddedRowID)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.displayedColumns.map(\.id))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.displayedRows.map(\.id))
    }

    private func headerCell(_ column: AmountColumn) -> some View {
        let added = store.recentlyAddedColumnID == column.id
        return Text(Formatters.usdHeader(column.usd))
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .pill(cellColor(flash: false, added: added))
    }

    private func dateCell(_ row: DateRow) -> some View {
        let added = store.recentlyAddedRowID == row.id
        return Text(Formatters.dayKey(row.date))
            .font(.system(.body, design: .monospaced))
            .pill(cellColor(flash: false, added: added))
    }

    private func valueCell(row: DateRow, column: AmountColumn) -> some View {
        let key = Store.cellKey(columnID: column.id, date: row.date)
        let isFlash = store.flashCellKey == key
        let isAdded = store.recentlyAddedColumnID == column.id || store.recentlyAddedRowID == row.id
        let color = cellColor(flash: isFlash, added: isAdded)

        return Group {
            if let cad = store.cadValue(usd: column.usd, date: row.date) {
                Button {
                    store.copyCell(column: column, date: row.date)
                } label: {
                    Text(Formatters.cadDisplay(cad))
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to copy \(Formatters.cadPlain(cad))")
            } else {
                Text("…")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .pill(color)
    }

    private func cellColor(flash: Bool, added: Bool) -> Color {
        if flash { return Color.green.opacity(0.55) }
        if added { return Color.accentColor.opacity(0.28) }
        return .clear
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Copy a number to add a column")
                .foregroundStyle(.secondary)
            Text("Copy a date to add a row")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("Copy hotkey:")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HotKeyRecorder(display: store.hotKeyConfig.display) { store.setHotKey($0) }
                .frame(width: 110, height: 22)
            Text("→ latest × topmost")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            if store.hiddenColumnCount > 0 || store.hiddenRowCount > 0 {
                Text("+\(store.hiddenColumnCount) cols · +\(store.hiddenRowCount) rows hidden")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private extension View {
    /// A rounded, padded background used to render the per-cell highlight.
    func pill(_ color: Color) -> some View {
        padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(color))
    }
}
