import SwiftUI

struct PicDimensionsRow: View {

    var pixelSize: CGSize

    private let maxBoxSide: CGFloat = 64.0
    private let minBoxSide: CGFloat = 6.0
    private let labelSpacing: CGFloat = 4.0

    var width: Int { Int(pixelSize.width) }
    var height: Int { Int(pixelSize.height) }

    var boxSize: CGSize {
        let scale = maxBoxSide / max(pixelSize.width, pixelSize.height)
        return CGSize(width: max(pixelSize.width * scale, minBoxSide),
                      height: max(pixelSize.height * scale, minBoxSide))
    }

    var megapixels: String {
        let value = Double(pixelSize.width * pixelSize.height) / 1_000_000.0
        return value.formatted(FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(value < 10.0 ? 1 : 0))) + " MP"
    }

    var aspectRatio: String? {
        func gcd(_ lhs: Int, _ rhs: Int) -> Int { rhs == 0 ? lhs : gcd(rhs, lhs % rhs) }
        let divisor = gcd(width, height)
        guard divisor > 0 else { return nil }
        let ratioWidth = width / divisor
        let ratioHeight = height / divisor
        guard max(ratioWidth, ratioHeight) <= 32 else { return nil }
        return "\(ratioWidth):\(ratioHeight)"
    }

    var body: some View {
        LabeledContent {
            box
        } label: {
            Text("Info.Dimensions", tableName: "ContentCredentials")
            Text(verbatim: [megapixels, aspectRatio].compactMap { $0 }.joined(separator: " · "))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Info.Dimensions", tableName: "ContentCredentials"))
        .accessibilityValue(Text(verbatim: "\(width) × \(height)"))
    }

    private var box: some View {
        RoundedRectangle(cornerRadius: 3.0)
            .fill(.tint.opacity(0.15))
            .strokeBorder(.tint, lineWidth: 1.5)
            .frame(width: boxSize.width, height: boxSize.height)
            .overlay(alignment: .top) {
                edgeLabel(width)
                    .alignmentGuide(.top) { $0[.bottom] + labelSpacing }
            }
            .overlay(alignment: .trailing) {
                edgeLabel(height)
                    .alignmentGuide(.trailing) { $0[.leading] - labelSpacing }
            }
            .padding(.top, 16.0)
            .padding(.trailing, 36.0)
            .padding(.vertical, 4.0)
            .frame(width: maxBoxSide + 36.0, alignment: .trailing)
    }

    private func edgeLabel(_ value: Int) -> some View {
        Text(verbatim: "\(value)")
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize()
    }
}
