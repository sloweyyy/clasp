import AppKit
import SwiftUI

enum ClaspBrand {
    static let accent = Color(red: 0.25, green: 0.38, blue: 0.98)
    static let accentSoft = Color(red: 0.43, green: 0.52, blue: 1.0)

    static let logo: NSImage? = {
        guard let url = Bundle.main.url(
            forResource: "ClaspLogo",
            withExtension: "png"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    static let breakBreathingCat: NSImage? = {
        guard let url = Bundle.main.url(
            forResource: "BreakBreathingCat-Mochi",
            withExtension: "png"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    static let menuBarIcon: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(
                    x: rect.minX + (rect.width * x),
                    y: rect.maxY - (rect.height * y)
                )
            }

            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 2.4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            path.move(to: point(0.72, 0.50))
            path.line(to: point(0.72, 0.30))
            path.curve(
                to: point(0.28, 0.30),
                controlPoint1: point(0.72, 0.12),
                controlPoint2: point(0.28, 0.12)
            )
            path.line(to: point(0.28, 0.70))
            path.curve(
                to: point(0.72, 0.70),
                controlPoint1: point(0.28, 0.90),
                controlPoint2: point(0.72, 0.90)
            )

            path.move(to: point(0.28, 0.52))
            path.curve(
                to: point(0.72, 0.50),
                controlPoint1: point(0.43, 0.36),
                controlPoint2: point(0.56, 0.66)
            )
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clasp"
        return image
    }()
}

struct ClaspLogoView: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let logo = ClaspBrand.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "paperclip")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct ClaspBrandHeader: View {
    let subtitle: String
    var logoSize: CGFloat = 38

    var body: some View {
        HStack(spacing: 12) {
            ClaspLogoView(size: logoSize)
            VStack(alignment: .leading, spacing: 1) {
                Text("Clasp")
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

struct ClaspBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    ClaspBrand.accent.opacity(0.10),
                    ClaspBrand.accentSoft.opacity(0.035),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )

            Circle()
                .fill(ClaspBrand.accentSoft.opacity(0.07))
                .frame(width: 420, height: 420)
                .blur(radius: 80)
                .offset(x: 360, y: -240)
        }
        .ignoresSafeArea()
    }
}

private struct ClaspCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.075), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.055), radius: 18, y: 8)
    }
}

extension View {
    func claspCard(padding: CGFloat = 18) -> some View {
        modifier(ClaspCardModifier(padding: padding))
    }
}

struct ClaspSectionHeading: View {
    let icon: String
    let title: String
    let subtitle: String?

    init(_ title: String, icon: String, subtitle: String? = nil) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ClaspBrand.accent)
                .frame(width: 30, height: 30)
                .background(ClaspBrand.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

struct ClaspStatusBanner: View {
    let message: String
    var isError = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "info.circle.fill")
                .foregroundStyle(isError ? Color.red : ClaspBrand.accent)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            (isError ? Color.red : ClaspBrand.accent).opacity(0.075),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityLabel("Status: \(message)")
    }
}
