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
        Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("Date")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.leading)
                ForEach(store.displayedColumns) { column in
                    Text(Formatters.usdHeader(column.usd))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            Divider().gridCellColumns(store.displayedColumns.count + 1)

            ForEach(store.displayedRows) { row in
                GridRow {
                    Text(Formatters.dayKey(row.date))
                        .font(.system(.body, design: .monospaced))
                        .gridColumnAlignment(.leading)
                    ForEach(store.displayedColumns) { column in
                        cell(usd: column.usd, date: row.date)
                    }
                }
            }
        }
    }

    private func cell(usd: Double, date: Date) -> some View {
        Group {
            if let cad = store.cadValue(usd: usd, date: date) {
                Button {
                    Clipboard.shared.copy(Formatters.cadPlain(cad))
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
        HStack {
            Text("⌘⇧C copies latest × topmost")
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
