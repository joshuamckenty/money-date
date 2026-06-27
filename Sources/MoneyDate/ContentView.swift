import SwiftUI
import AppKit

/// Fixed cell metrics so the three frozen panes (header row, date column, data grid) align exactly.
private enum Metrics {
    static let dateCol: CGFloat = 100
    static let valueCol: CGFloat = 150
    static let row: CGFloat = 26
    static let header: CGFloat = 24
}

/// Reports the data scroll view's content origin so the frozen panes can track it.
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}

struct ContentView: View {
    @ObservedObject var store: Store

    @State private var hoveredColumnID: UUID?
    @State private var hoveredRowID: UUID?
    @State private var showAddDate = false
    @State private var newDate = Date()
    @State private var scrollOffset: CGPoint = .zero

    private var years: [Int] {
        let current = DateUtils.calendar.component(.year, from: Date())
        return Array((current - 25)...(current + 1)).reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls

            Divider()

            if store.displayedRows.isEmpty && store.displayedColumns.isEmpty {
                emptyState
            } else {
                table
            }

            footer
        }
        .padding(12)
        .frame(minWidth: 420, minHeight: 260)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button("Reset dates") { store.resetDates() }

            Button("Add date…") { showAddDate = true }
                .popover(isPresented: $showAddDate, arrowEdge: .bottom) { addDatePopover }

            Picker("Year", selection: $store.selectedYear) {
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 90)
            .onChange(of: store.selectedYear) { newValue in
                store.populate(year: newValue)
            }

            Spacer()

            currencyPicker(selection: Binding(
                get: { store.fromCurrency },
                set: { store.setCurrencies(from: $0, to: store.toCurrency) }))
            Text("→").foregroundStyle(.secondary)
            currencyPicker(selection: Binding(
                get: { store.toCurrency },
                set: { store.setCurrencies(from: store.fromCurrency, to: $0) }))
        }
    }

    private func currencyPicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(Currency.all, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .frame(width: 76)
    }

    private var addDatePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Date", selection: $newDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Spacer()
                Button("Add") {
                    store.addRow(date: newDate)
                    showAddDate = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    // MARK: - Frozen-pane table

    private var table: some View {
        // Left pane (corner + date column) is frozen at the left edge — it lives
        // OUTSIDE the horizontal scroll. The header row and the data rows share ONE
        // horizontal scroll, so they can never desync horizontally. The only sync
        // left is the date column tracking the data's vertical scroll.
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                cornerCell
                Divider().frame(width: Metrics.dateCol)
                dateColumn
            }
            .frame(width: Metrics.dateCol)

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    Divider()
                    dataBody
                }
            }
        }
        .animation(.easeOut(duration: 0.45), value: store.flashCellKey)
        .animation(.easeOut(duration: 0.9), value: store.recentlyAddedColumnID)
        .animation(.easeOut(duration: 0.9), value: store.recentlyAddedRowID)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.displayedColumns.map(\.id))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.displayedRows.map(\.id))
    }

    private var cornerCell: some View {
        Text("Date")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(width: Metrics.dateCol, height: Metrics.header, alignment: .leading)
            .background(AnchorReporter { point in
                // Nudge from the corner cell's upper-left toward its center: half a
                // corner-cell width right and half its height down (screen y is up).
                store.setAddAnchor(CGPoint(x: point.x + Metrics.dateCol / 2,
                                           y: point.y - Metrics.header / 2))
            })
    }

    /// Frozen date column; tracks the data body's vertical scroll.
    private var dateColumn: some View {
        VStack(spacing: 0) {
            ForEach(store.displayedRows) { dateCell($0) }
        }
        .frame(width: Metrics.dateCol, alignment: .top)
        .offset(y: scrollOffset.y)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    /// USD header row; pinned vertically (outside the vertical scroll), scrolls horizontally.
    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(store.displayedColumns) { headerCell($0) }
        }
        .frame(height: Metrics.header)
    }

    /// Vertically-scrolling data rows; the vertical scroll indicator lives here.
    private var dataBody: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                ForEach(store.displayedRows) { row in
                    HStack(spacing: 0) {
                        ForEach(store.displayedColumns) { column in
                            valueCell(row: row, column: column)
                        }
                    }
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("vbody")).origin)
                }
            )
        }
        .coordinateSpace(name: "vbody")
        .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
    }

    // MARK: - Cells

    private func headerCell(_ column: AmountColumn) -> some View {
        let added = store.recentlyAddedColumnID == column.id
        return ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 4).fill(cellColor(flash: false, added: added))
            Text(Formatters.amount(column.usd, code: store.fromCurrency))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.trailing, 6)
        }
        .overlay(alignment: .topTrailing) {
            if hoveredColumnID == column.id {
                deleteButton("Delete column") { store.deleteColumn(id: column.id) }
            }
        }
        .frame(width: Metrics.valueCol, height: Metrics.header)
        .contentShape(Rectangle())
        .onHover { hoveredColumnID = $0 ? column.id : nil }
    }

    private func dateCell(_ row: DateRow) -> some View {
        let added = store.recentlyAddedRowID == row.id
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(cellColor(flash: false, added: added))
            Text(Formatters.dayKey(row.date))
                .font(.system(.body, design: .monospaced))
                .padding(.leading, 4)
        }
        .overlay(alignment: .trailing) {
            if hoveredRowID == row.id {
                deleteButton("Delete row") { store.deleteRow(id: row.id) }
            }
        }
        .frame(width: Metrics.dateCol, height: Metrics.row)
        .contentShape(Rectangle())
        .onHover { hoveredRowID = $0 ? row.id : nil }
    }

    private func valueCell(row: DateRow, column: AmountColumn) -> some View {
        let key = Store.cellKey(columnID: column.id, date: row.date)
        let isFlash = store.flashCellKey == key
        let isAdded = store.recentlyAddedColumnID == column.id || store.recentlyAddedRowID == row.id
        let color = cellColor(flash: isFlash, added: isAdded)

        return ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 4).fill(color)
            if let value = store.convertedValue(amount: column.usd, date: row.date) {
                Button {
                    store.copyCell(column: column, date: row.date, at: NSEvent.mouseLocation)
                } label: {
                    Text(Formatters.amount(value, code: store.toCurrency))
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to copy \(Formatters.plain(value))")
            } else {
                Text("…")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 6)
            }
        }
        .frame(width: Metrics.valueCol, height: Metrics.row)
    }

    private func deleteButton(_ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
        }
        .buttonStyle(.plain)
        .padding(1)
        .help(help)
    }

    private func cellColor(flash: Bool, added: Bool) -> Color {
        if flash { return Color.green.opacity(0.55) }
        if added { return Color.accentColor.opacity(0.28) }
        return .clear
    }

    // MARK: - Empty state & footer

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Copy a number to add a column")
                .foregroundStyle(.secondary)
            Text("Copy or “Add date…” to add a row")
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
            Text("build \(Self.buildStamp)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Build time of the running binary (its modification date) — lets you confirm
    /// which build is live.
    private static let buildStamp: String = {
        guard let url = Bundle.main.executableURL,
              let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate else { return "?" }
        let df = DateFormatter()
        df.dateFormat = "MMM d HH:mm:ss"
        return df.string(from: date)
    }()
}

/// Reports its on-screen center (screen coords, bottom-left origin, matching
/// NSEvent.mouseLocation) whenever it moves or lays out — used to anchor the
/// "add" confetti at the table corner where new rows/columns appear.
struct AnchorReporter: NSViewRepresentable {
    var onChange: (CGPoint) -> Void

    func makeNSView(context: Context) -> ReporterNSView {
        let view = ReporterNSView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReporterNSView, context: Context) {
        view.onChange = onChange
        view.report()
    }

    final class ReporterNSView: NSView {
        var onChange: ((CGPoint) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); report() }
        override func layout() { super.layout(); report() }
        func report() {
            guard let window else { return }
            let inWindow = convert(bounds, to: nil)
            let onScreen = window.convertToScreen(inWindow)
            onChange?(CGPoint(x: onScreen.midX, y: onScreen.midY))
        }
    }
}
