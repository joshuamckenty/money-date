import SwiftUI
import AppKit

/// Fixed cell metrics so the three frozen panes (header row, date column, data grid) align exactly.
enum Metrics {
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
        return Array((current - 25)...current).reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

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

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("money-date")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Color.accentColor)
            Text("Currency conversions across fixed dates — copy a number to add a column, a date to add a row.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
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
        // horizontal scroll, so they can never desync horizontally. A GeometryReader
        // bounds the data area's height so the vertical ScrollView always scrolls
        // (even in a very small window). The date column tracks the body's scroll.
        GeometryReader { geo in
            let dataAreaHeight = max(0, geo.size.height - Metrics.header - 1)
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    cornerCell
                    Divider().frame(width: Metrics.dateCol)
                    dateColumn(height: dataAreaHeight)
                }
                .frame(width: Metrics.dateCol)

                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        headerRow
                        Divider()
                        dataBody(height: dataAreaHeight)
                    }
                }
            }
            // Full table rect (date col + visible value viewport), for row-delete centering.
            .background(AnchorReporter { store.setTableRect($0) })
            .animation(.easeOut(duration: 0.45), value: store.flashCellKey)
            .animation(.easeOut(duration: 0.9), value: store.recentlyAddedColumnID)
            .animation(.easeOut(duration: 0.9), value: store.recentlyAddedRowID)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.displayedColumns.map(\.id))
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.displayedRows.map(\.id))
        }
    }

    private var cornerCell: some View {
        Text("Date")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .frame(width: Metrics.dateCol, height: Metrics.header, alignment: .leading)
            .background(headerTint)
    }

    /// Frozen date column; tracks the data body's vertical scroll.
    private func dateColumn(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(store.displayedRows.enumerated()), id: \.element.id) { index, row in
                dateCell(row).background(rowFill(index))
            }
        }
        .frame(width: Metrics.dateCol, alignment: .top)
        .offset(y: scrollOffset.y)
        .frame(width: Metrics.dateCol, height: height, alignment: .top)
        .clipped()
    }

    /// USD header row; pinned vertically (outside the vertical scroll), scrolls horizontally.
    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(store.displayedColumns) { headerCell($0) }
        }
        .frame(height: Metrics.header)
        .background(headerTint)
    }

    /// Vertically-scrolling data rows (height-bounded so the scroller shows).
    private func dataBody(height: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                ForEach(Array(store.displayedRows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 0) {
                        ForEach(store.displayedColumns) { column in
                            valueCell(row: row, column: column)
                        }
                    }
                    .background(rowFill(index))
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("vbody")).origin)
                }
            )
            // The value-cells block in screen coords; column/row/cell centers are
            // computed from this so effects land exactly on the right cell/column.
            .background(AnchorReporter { store.setDataRect($0) })
        }
        .frame(height: height)
        .coordinateSpace(name: "vbody")
        .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
    }

    // MARK: - Cells

    private func headerCell(_ column: AmountColumn) -> some View {
        let added = store.recentlyAddedColumnID == column.id
        let deleteHover = hoveredColumnID == column.id
        return ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 4)
                .fill(deleteHover ? deleteHoverColor : cellColor(flash: false, added: added))
            Text(Formatters.amount(column.usd, code: store.fromCurrency))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.trailing, 6)
        }
        .frame(width: Metrics.valueCol, height: Metrics.header)
        .overlay(alignment: .leading) { columnSeparator }
        .contentShape(Rectangle())
        .onHover { hoveredColumnID = $0 ? column.id : nil }
        .onTapGesture { store.deleteColumn(id: column.id, at: NSEvent.mouseLocation) }
        .help("Click to delete this column")
    }

    private func dateCell(_ row: DateRow) -> some View {
        let added = store.recentlyAddedRowID == row.id
        let deleteHover = hoveredRowID == row.id
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(deleteHover ? deleteHoverColor : cellColor(flash: false, added: added))
            Text(Formatters.displayDate(row.date, format: store.dateFormat))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.leading, 4)
        }
        .frame(width: Metrics.dateCol, height: Metrics.row)
        .contentShape(Rectangle())
        .onHover { hoveredRowID = $0 ? row.id : nil }
        .onTapGesture { store.deleteRow(id: row.id, at: NSEvent.mouseLocation) }
        .help("Click to delete this row")
    }

    private func valueCell(row: DateRow, column: AmountColumn) -> some View {
        let key = Store.cellKey(columnID: column.id, date: row.date)
        let isFlash = store.flashCellKey == key
        let isAdded = store.recentlyAddedColumnID == column.id || store.recentlyAddedRowID == row.id
        let isHover = hoveredRowID == row.id || hoveredColumnID == column.id
        let color = cellColor(flash: isFlash, added: isAdded, hover: isHover)

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
        .overlay(alignment: .leading) { columnSeparator }
    }

    /// Subtle vertical divider between columns / very subtle row striping / header tint.
    private var columnSeparator: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5)
    }

    private func rowFill(_ index: Int) -> Color {
        index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04)
    }

    private var headerTint: Color { Color.accentColor.opacity(0.10) }

    /// Themed-red fill for the delete-on-hover header/date cells.
    private var deleteHoverColor: Color { Color.red.opacity(0.35) }

    private func cellColor(flash: Bool, added: Bool, hover: Bool = false) -> Color {
        if flash { return Color.green.opacity(0.55) }
        if added { return Color.accentColor.opacity(0.28) }
        if hover { return Color.accentColor.opacity(0.12) }
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
            VStack(alignment: .trailing, spacing: 1) {
                if store.hiddenColumnCount > 0 || store.hiddenRowCount > 0 {
                    Text("+\(store.hiddenColumnCount) cols · +\(store.hiddenRowCount) rows hidden")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text("© 2026 Joshua McKenty")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("build \(Self.buildStamp)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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

/// Reports its on-screen frame (screen coords, bottom-left origin, matching
/// NSEvent.mouseLocation) whenever it moves or lays out — used to compute exact
/// effect anchors (column/row/cell centers) from the data-cells block.
struct AnchorReporter: NSViewRepresentable {
    var onChange: (CGRect) -> Void

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
        var onChange: ((CGRect) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                // Re-report when the panel moves or changes display, so the
                // screen-coords anchor stays correct across screens.
                for note in [NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification] {
                    NotificationCenter.default.addObserver(self, selector: #selector(report),
                                                           name: note, object: window)
                }
            }
            // Re-report on every scroll tick (horizontal AND vertical) by observing
            // each enclosing clip view's bounds change — SwiftUI scrolling doesn't
            // otherwise re-render, which left the reported rect one fire stale.
            var ancestor = superview
            while let view = ancestor {
                if let clip = view as? NSClipView {
                    clip.postsBoundsChangedNotifications = true
                    NotificationCenter.default.addObserver(self, selector: #selector(report),
                                                           name: NSView.boundsDidChangeNotification, object: clip)
                }
                ancestor = view.superview
            }
            report()
        }

        override func layout() { super.layout(); report() }

        @objc func report() {
            guard let window else { return }
            onChange?(window.convertToScreen(convert(bounds, to: nil)))
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
