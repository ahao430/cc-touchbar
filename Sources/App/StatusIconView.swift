import AppKit
import QuartzCore

@MainActor
final class StatusIconView: NSView {

    enum Mode: String {
        case idle
        case thinking
        case streaming
        case stopped
        case offline
    }

    private let dot = CAShapeLayer()
    private var currentMode: Mode = .offline

    /// 让 NSCustomTouchBarItem 按 18pt 宽排布，不要默认拉宽到 ~44pt
    override var intrinsicContentSize: NSSize {
        NSSize(width: 18, height: 18)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupDot()
        update(mode: .idle)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupDot()
        update(mode: .idle)
    }

    private func setupDot() {
        let radius: CGFloat = 5
        let path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius*2, height: radius*2), transform: nil)
        dot.path = path
        dot.fillColor = NSColor.systemGray.cgColor
        dot.position = CGPoint(x: bounds.midX, y: bounds.midY)
        layer?.addSublayer(dot)
    }

    func update(mode: Mode) {
        guard mode != currentMode else { return }
        currentMode = mode
        dot.removeAllAnimations()

        switch mode {
        case .idle:
            dot.fillColor = NSColor.systemGray.cgColor
        case .thinking:
            dot.fillColor = NSColor.systemBlue.cgColor
            startPulse(duration: 0.8)
        case .streaming:
            dot.fillColor = NSColor.systemGreen.cgColor
            startPulse(duration: 0.4)
        case .stopped:
            dot.fillColor = NSColor.systemRed.cgColor
        case .offline:
            dot.fillColor = NSColor.tertiaryLabelColor.cgColor
        }
    }

    private func startPulse(duration: CFTimeInterval) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.3
        anim.duration = duration
        anim.autoreverses = true
        anim.repeatCount = .infinity
        dot.add(anim, forKey: "pulse")
    }
}
