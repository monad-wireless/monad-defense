import SwiftUI

// MARK: - TableFigureView
//
// Values that are a list, not a shape.
//
// A phone is narrow, and a table that scrolls sideways hides its last column
// behind a gesture nobody performs — so this widget never scrolls. It picks a
// layout instead:
//
//   up to three columns  → a Grid, cells wrapping, sized to the width
//   four or more         → one stacked block per row, first cell as its title
//
// The stacked form is what a table becomes on a narrow screen anyway. Making
// that explicit is better than letting a Grid overflow and calling it
// scrollable.

struct TableFigureView: View {
    let table: TableFigure
    var tint: Color = Theme.accent

    /// Beyond this, columns cannot share a phone's width legibly.
    private var fitsAsGrid: Bool { table.columns.count <= 3 }

    var body: some View {
        if fitsAsGrid {
            gridLayout
        } else {
            stackedLayout
        }
    }

    // MARK: Layouts

    private var gridLayout: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(table.columns.enumerated()), id: \.offset) { _, column in
                    Text(column)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 6)

            ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                        cellText(cell, column: column, row: index)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().padding(.vertical, 8) }
                VStack(alignment: .leading, spacing: 5) {
                    // The first cell names the row; the rest describe it.
                    Text(cardMarkdown(row.first ?? ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            table.emphasis.contains(index) ? AnyShapeStyle(tint) : AnyShapeStyle(.primary))
                    ForEach(Array(row.dropFirst().enumerated()), id: \.offset) { offset, cell in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(table.columns[offset + 1])
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                                .frame(width: 74, alignment: .leading)
                            Text(cardMarkdown(cell))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func cellText(_ cell: String, column: Int, row: Int) -> some View {
        Text(cardMarkdown(cell))
            .font(.footnote)
            // The first column is the row's name; the rest are its values, so
            // the name carries the weight and the values stay quiet.
            .fontWeight(column == 0 ? .medium : .regular)
            .foregroundStyle(
                table.emphasis.contains(row)
                    ? AnyShapeStyle(tint)
                    : AnyShapeStyle(column == 0 ? .primary : .secondary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
