import AppKit

final class CandidatePanel {
    static let shared = CandidatePanel()

    private let panel: NSPanel
    private let view: CandidateView

    private init() {
        view = CandidateView(frame: .zero)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = view
        panel.ignoresMouseEvents = false
    }

    var isVisible: Bool { panel.isVisible }

    func hide() {
        panel.orderOut(nil)
    }

    func update(segmented: String, candidates: [Candidate], selected: Int, page: Int, pageSize: Int) {
        view.segmented = segmented
        view.candidates = candidates
        view.selected = selected
        view.needsDisplay = true
        let size = view.preferredSize
        var frame = panel.frame
        frame.size = size
        panel.setFrame(frame, display: true)
        view.frame = NSRect(origin: .zero, size: size)
    }

    func show(near caret: NSRect) {
        let size = view.preferredSize
        var origin = CGPoint(x: caret.minX, y: caret.minY - size.height - 4)
        if let screen = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame {
            if origin.y < screen.minY {
                origin.y = caret.maxY + 4
            }
            if origin.x + size.width > screen.maxX {
                origin.x = max(screen.minX, screen.maxX - size.width - 8)
            }
            if origin.x < screen.minX {
                origin.x = screen.minX + 8
            }
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        view.frame = NSRect(origin: .zero, size: size)
        panel.orderFront(nil)
    }
}

private final class CandidateView: NSView {
    var segmented = ""
    var candidates: [Candidate] = []
    var selected = 0

    private let rowHeight: CGFloat = 24
    private let headerHeight: CGFloat = 26
    private let inset: CGFloat = 10
    private let highlight = NSColor(calibratedRed: 42 / 255, green: 142 / 255, blue: 142 / 255, alpha: 1)
    private let panelFill = NSColor(calibratedWhite: 0.12, alpha: 0.96)
    private let glossColor = NSColor(calibratedWhite: 0.72, alpha: 1)

    var preferredSize: NSSize {
        let rows = max(candidates.count, 1)
        let width = max(measuredWidth(), 240)
        let height = headerHeight + CGFloat(rows) * rowHeight + 10
        return NSSize(width: width, height: height)
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        panelFill.setFill()
        path.fill()
        NSColor(calibratedWhite: 0.25, alpha: 0.8).setStroke()
        path.lineWidth = 1
        path.stroke()

        let headerRect = NSRect(x: inset, y: 6, width: bounds.width - inset * 2, height: headerHeight - 6)
        let header = NSMutableAttributedString(
            string: segmented.isEmpty ? " " : segmented,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
        )
        header.draw(with: headerRect, options: [.usesLineFragmentOrigin])

        var y = headerHeight
        for (idx, cand) in candidates.enumerated() {
            let row = NSRect(x: 4, y: y, width: bounds.width - 8, height: rowHeight)
            if idx == selected {
                let hi = NSBezierPath(roundedRect: row, xRadius: 4, yRadius: 4)
                highlight.setFill()
                hi.fill()
            }
            let line = Self.attributedRow(index: idx + 1, candidate: cand, selected: idx == selected, glossColor: glossColor)
            let textRect = NSRect(x: inset, y: y + 3, width: bounds.width - inset * 2, height: rowHeight - 4)
            line.draw(with: textRect, options: [.usesLineFragmentOrigin])
            y += rowHeight
        }
    }

    private func measuredWidth() -> CGFloat {
        var width: CGFloat = 180
        let header = NSAttributedString(
            string: segmented,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)]
        )
        width = max(width, header.size().width + inset * 2 + 16)
        for (idx, cand) in candidates.enumerated() {
            let line = Self.attributedRow(index: idx + 1, candidate: cand, selected: false, glossColor: glossColor)
            width = max(width, line.size().width + inset * 2 + 16)
        }
        return min(width, 560)
    }

    private static func attributedRow(index: Int, candidate: Candidate, selected: Bool, glossColor: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let primary = selected ? NSColor.white : NSColor.white
        let secondary = selected ? NSColor(calibratedWhite: 0.92, alpha: 1) : glossColor
        out.append(NSAttributedString(
            string: "\(index) ",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: primary,
            ]
        ))
        out.append(NSAttributedString(
            string: candidate.phrase,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: primary,
            ]
        ))
        if !candidate.gloss.isEmpty {
            out.append(NSAttributedString(
                string: "  \(candidate.gloss)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: secondary,
                ]
            ))
        }
        return out
    }
}
