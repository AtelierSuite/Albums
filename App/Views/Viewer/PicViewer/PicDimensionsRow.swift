import SwiftUI

struct PicDimensionsRow: View {

    var pixelSize: CGSize

    @ScaledMetric(relativeTo: .caption2) private var maxBoxSide: CGFloat = 64.0
    @ScaledMetric(relativeTo: .caption2) private var minBoxSide: CGFloat = 6.0
    @ScaledMetric(relativeTo: .caption2) private var labelSpacing: CGFloat = 4.0

    var width: Int { Int(pixelSize.width) }
    var height: Int { Int(pixelSize.height) }

    var boxSize: CGSize {
        let scale = maxBoxSide / max(pixelSize.width, pixelSize.height)
        return CGSize(width: max(pixelSize.width * scale, minBoxSide),
                      height: max(pixelSize.height * scale, minBoxSide))
    }

    var megapixels: String? {
        let value = Double(pixelSize.width * pixelSize.height) / 1_000_000.0
        guard value >= 0.1 else { return nil }
        return value.formatted(FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(value < 10.0 ? 1 : 0))) + " MP"
    }

    var aspectRatio: String? {
        func gcd(_ lhs: Int, _ rhs: Int) -> Int { rhs == 0 ? lhs : gcd(rhs, lhs % rhs) }
        let divisor = gcd(width, height)
        guard divisor > 0 else { return nil }
        let ratioWidth = width / divisor
        let ratioHeight = height / divisor
        guard min(ratioWidth, ratioHeight) <= 20 else { return nil }
        return "\(ratioWidth):\(ratioHeight)"
    }

    var subtitle: String? {
        let parts = [megapixels, aspectRatio].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        LabeledContent {
            box
        } label: {
            Text("Info.Dimensions", tableName: "ContentCredentials")
            if let subtitle {
                Text(verbatim: subtitle)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Info.Dimensions", tableName: "ContentCredentials"))
        .accessibilityValue(Text(verbatim: "\(width) × \(height)"))
    }

    private var box: some View {
        Grid(horizontalSpacing: labelSpacing, verticalSpacing: labelSpacing) {
            GridRow {
                edgeLabel(width)
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
            }
            GridRow {
                RoundedRectangle(cornerRadius: 3.0)
                    .fill(.tint.opacity(0.15))
                    .strokeBorder(.tint, lineWidth: 1.5)
                    .frame(width: boxSize.width, height: boxSize.height)
                edgeLabel(height)
                    .gridColumnAlignment(.leading)
            }
        }
        .padding(.vertical, 4.0)
    }

    private func edgeLabel(_ value: Int) -> some View {
        Text(verbatim: "\(value)")
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize()
    }
}
