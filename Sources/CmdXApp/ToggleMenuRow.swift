import AppKit

/// A menu row that behaves like a System Settings switch: a fixed shortcut
/// column, a label, and a toggle pinned to the trailing edge.
///
/// This is a custom `NSView` rather than a stateful `NSMenuItem` for one
/// practical reason — clicking an ordinary menu item dismisses the whole menu,
/// so flipping two switches means opening the menu twice. A view-based item
/// handles its own mouse events, so the menu stays open and you can keep
/// clicking.
///
/// The fixed-width shortcut column is what keeps the labels aligned; padding
/// strings with spaces only lines up in a monospaced font, which menus are not.
@MainActor
final class ToggleMenuRow: NSView {
    private let shortcut: String
    private let label: String
    private let onToggle: (Bool) -> Void

    private var isOn: Bool
    private var isHighlighted = false

    private static let rowHeight: CGFloat = 24
    private static let rowWidth: CGFloat = 274
    private static let leadingInset: CGFloat = 14
    private static let trailingInset: CGFloat = 12
    /// Labels start at the leading edge; shortcuts sit in their own column after
    /// the longest label. Both are fixed widths rather than measured, because a
    /// row cannot see its siblings and space-padding only lines up in a
    /// monospaced font.
    private static let labelColumn: CGFloat = 150
    private static let shortcutColumn: CGFloat = 72
    private static let toggleSize = NSSize(width: 26, height: 14)

    init(shortcut: String, label: String, isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        self.shortcut = shortcut
        self.label = label
        self.isOn = isOn
        self.onToggle = onToggle
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: Self.rowHeight))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func setOn(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        needsDisplay = true
    }

    // MARK: - Interaction

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
    }

    /// Deliberately does not call `menu?.cancelTracking()` — that is what would
    /// close the menu after a single click.
    override func mouseUp(with event: NSEvent) {
        isOn.toggle()
        needsDisplay = true
        onToggle(isOn)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let textColor: NSColor = isHighlighted ? .selectedMenuItemTextColor : .labelColor

        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: 5, dy: 1),
                xRadius: 4, yRadius: 4
            ).fill()
        }

        let font = NSFont.menuFont(ofSize: 0)
        let baseline = (bounds.height - font.capHeight) / 2 - font.descender / 2 - 1

        draw(label,
             at: NSPoint(x: Self.leadingInset, y: baseline),
             font: font,
             color: textColor)

        // Shortcut column, dimmed so the label still reads first.
        draw(shortcut,
             at: NSPoint(x: Self.leadingInset + Self.labelColumn, y: baseline),
             font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular),
             color: textColor.withAlphaComponent(isHighlighted ? 0.85 : 0.55))

        drawToggle(tint: textColor)
    }

    private func draw(_ string: String, at point: NSPoint, font: NSFont, color: NSColor) {
        (string as NSString).draw(
            at: point,
            withAttributes: [.font: font, .foregroundColor: color])
    }

    /// Grayscale on purpose: colour in a menu row competes with the system's own
    /// highlight. Tone carries the state, and knob position carries it again for
    /// anyone who can't separate the two tones.
    private func drawToggle(tint: NSColor) {
        let size = Self.toggleSize
        let track = NSRect(
            x: bounds.maxX - Self.trailingInset - size.width,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        ).insetBy(dx: 0.5, dy: 0.5)

        let radius = track.height / 2
        let pill = NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius)

        // On reads light and open; off reads dense and closed.
        tint.withAlphaComponent(isOn ? 0.14 : 0.38).setFill()
        pill.fill()
        tint.withAlphaComponent(isOn ? 0.30 : 0.45).setStroke()
        pill.lineWidth = 1
        pill.stroke()

        let inset: CGFloat = 2
        let diameter = track.height - inset * 2
        let x = isOn ? track.maxX - diameter - inset : track.minX + inset
        tint.withAlphaComponent(0.75).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: x, y: track.minY + inset, width: diameter, height: diameter)).fill()
    }
}
