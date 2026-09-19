import Foundation

indirect enum LayoutSpec {
    case pane
    case split(vertical: Bool, fraction: Double, LayoutSpec, LayoutSpec)
    var paneCount: Int {
        switch self { case .pane: return 1; case let .split(_, _, a, b): return a.paneCount + b.paneCount }
    }
    static func line(_ nodes: [LayoutSpec], vertical: Bool) -> LayoutSpec {
        guard nodes.count > 1 else { return nodes.first ?? .pane }
        return .split(vertical: vertical, fraction: 1 / Double(nodes.count), nodes[0], line(Array(nodes.dropFirst()), vertical: vertical))
    }
}

enum LayoutPreset: String, CaseIterable {
    case single, columns, rows, four, sixWide, sixTall, leftMain, rightMain, topMain, bottomMain, threeColumns
    var title: String {
        switch self {
        case .single: return "Single Pane"
        case .columns: return "Two Columns"
        case .rows: return "Two Rows"
        case .four: return "Four Panes · 2 Columns × 2 Rows"
        case .sixWide: return "Six Panes · 3 Columns × 2 Rows"
        case .sixTall: return "Six Panes · 2 Columns × 3 Rows"
        case .leftMain: return "Large Left, Two Right"
        case .rightMain: return "Two Left, Large Right"
        case .topMain: return "Large Top, Two Bottom"
        case .bottomMain: return "Two Top, Large Bottom"
        case .threeColumns: return "Three Columns"
        }
    }
    var symbol: String {
        switch self {
        case .single: return "rectangle"
        case .columns: return "rectangle.split.2x1"
        case .rows: return "rectangle.split.1x2"
        case .four: return "square.grid.2x2"
        case .sixWide, .sixTall: return "square.grid.3x2"
        case .threeColumns: return "rectangle.split.3x1"
        default: return "rectangle.3.group"
        }
    }
    var spec: LayoutSpec {
        let pair = LayoutSpec.line([.pane, .pane], vertical: false)
        let horizontalPair = LayoutSpec.line([.pane, .pane], vertical: true)
        switch self {
        case .single: return .pane
        case .columns: return horizontalPair
        case .rows: return pair
        case .four: return .line([pair, pair], vertical: true)
        case .sixWide: return .line([pair, pair, pair], vertical: true)
        case .sixTall: return .line([horizontalPair, horizontalPair, horizontalPair], vertical: false)
        case .leftMain: return .split(vertical: true, fraction: 0.6, .pane, pair)
        case .rightMain: return .split(vertical: true, fraction: 0.4, pair, .pane)
        case .topMain: return .split(vertical: false, fraction: 0.6, .pane, horizontalPair)
        case .bottomMain: return .split(vertical: false, fraction: 0.4, horizontalPair, .pane)
        case .threeColumns: return .line([.pane, .pane, .pane], vertical: true)
        }
    }
}
