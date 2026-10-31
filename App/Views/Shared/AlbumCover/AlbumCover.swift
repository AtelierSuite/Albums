import Photos
import SwiftUI

enum AlbumCoverStyle {
    case stack
    case flat(cornerRadius: CGFloat = 10.0)
    case peek
    case mosaic
}

struct AlbumCover: View {

    var name: String
    var length: CGFloat?
    var picCount: Int
    var albumCount: Int

    var primaryImage: Image?
    var secondaryImage: Image?
    var tertiaryImage: Image?
    var isDownloading: Bool = false
    var style: AlbumCoverStyle = .stack

    init(
        name: String,
        length: CGFloat? = nil,
        picCount: Int = 0,
        albumCount: Int = 0,
        primaryImage: Image? = nil,
        secondaryImage: Image? = nil,
        tertiaryImage: Image? = nil,
        isDownloading: Bool = false,
        style: AlbumCoverStyle = .stack
    ) {
        self.name = name
        self.length = length
        self.picCount = picCount
        self.albumCount = albumCount
        self.primaryImage = primaryImage
        self.secondaryImage = secondaryImage
        self.tertiaryImage = tertiaryImage
        self.isDownloading = isDownloading
        self.style = style
    }

    var body: some View {
        switch style {
        case .stack:
            stackBody
        case .flat(let cornerRadius):
            AlbumFlatCover(name: name, length: length, image: primaryImage,
                           cornerRadius: cornerRadius, isDownloading: isDownloading)
        case .peek:
            AlbumPeekCover(name: name, length: length, primaryImage: primaryImage,
                           secondaryImage: secondaryImage, tertiaryImage: tertiaryImage,
                           isDownloading: isDownloading)
        case .mosaic:
            AlbumMosaicCover(name: name, length: length, primaryImage: primaryImage,
                             secondaryImage: secondaryImage, tertiaryImage: tertiaryImage,
                             isDownloading: isDownloading)
        }
    }

    var stackBody: some View {
        Canvas { context, size in
            let itemCountTag = "itemCount"
            // The canvas is physically larger than the layout size (via frame/padding)
            // to prevent clipping of rotated cards and shadows. Scale factor undoes
            // the oversizing so cards appear at the intended 92% of layout size.
            let scale: CGFloat = 1.0 / 1.16
            let cardW = size.width * 0.92 * scale
            let cardH = size.height * 0.92 * scale
            let cornerRadius = size.height * 0.12 * scale
            let cardRect = CGRect(
                x: (size.width - cardW) / 2,
                y: (size.height - cardH) / 2,
                width: cardW,
                height: cardH
            )
            let cardPath = Path(
                roundedRect: cardRect,
                cornerRadius: cornerRadius,
                style: .continuous
            )

            let logicalH = size.height * scale
            let logicalW = size.width * scale

            if let tertiaryImage {
                drawRotatedCard(
                    context: context, size: size, image: tertiaryImage,
                    cardW: cardW, cardH: cardH, cornerRadius: cornerRadius,
                    angle: .degrees(-12),
                    shadowColor: .black.opacity(0.15), shadowRadius: 2, shadowY: logicalH * 0.01
                )
            }

            if let secondaryImage {
                drawRotatedCard(
                    context: context, size: size, image: secondaryImage,
                    cardW: cardW, cardH: cardH, cornerRadius: cornerRadius,
                    angle: .degrees(10),
                    shadowColor: .black.opacity(0.15), shadowRadius: 3, shadowY: logicalH * 0.02
                )
            }

            if let primaryImage {
                var front = context
                front.addFilter(.shadow(
                    color: .black.opacity(0.25), radius: 2, x: 0, y: logicalH * 0.015
                ))
                front.drawLayer { ctx in
                    ctx.clip(to: cardPath)

                    let resolved = ctx.resolve(primaryImage)
                    let srcSize = resolved.size
                    let scale = max(cardW / srcSize.width, cardH / srcSize.height)
                    let drawW = srcSize.width * scale
                    let drawH = srcSize.height * scale
                    let drawRect = CGRect(
                        x: cardRect.midX - drawW / 2,
                        y: cardRect.midY - drawH / 2,
                        width: drawW,
                        height: drawH
                    )
                    ctx.draw(resolved, in: drawRect)

                    if logicalW >= 80 {
                        let gradientRect = CGRect(
                            x: cardRect.minX,
                            y: cardRect.midY,
                            width: cardW,
                            height: cardH / 2
                        )
                        ctx.fill(
                            Path(gradientRect),
                            with: .linearGradient(
                                Gradient(colors: [.clear, .black.opacity(0.65)]),
                                startPoint: CGPoint(x: gradientRect.midX, y: gradientRect.minY),
                                endPoint: CGPoint(x: gradientRect.midX, y: gradientRect.maxY)
                            )
                        )
                    }

                    ctx.stroke(cardPath, with: .color(.primary.opacity(0.15)), lineWidth: 0.5)
                }
            } else {
                let gradColors = Color.gradient(from: name)
                var front = context
                front.addFilter(.shadow(
                    color: .black.opacity(0.25), radius: 2, x: 0, y: logicalH * 0.015
                ))
                front.fill(
                    cardPath,
                    with: .linearGradient(
                        Gradient(colors: [gradColors.primary, gradColors.secondary]),
                        startPoint: cardRect.origin,
                        endPoint: CGPoint(x: cardRect.maxX, y: cardRect.maxY)
                    )
                )
            }

            if isDownloading {
                context.fill(cardPath, with: .color(.black.opacity(0.3)))
            }

            if logicalW >= 80,
               let resolved = context.resolveSymbol(id: itemCountTag) {
                let countOrigin = CGPoint(
                    x: size.width / 2,
                    y: size.height / 2 + logicalH * (0.5 - 0.16)
                )
                context.draw(resolved, at: countOrigin, anchor: .center)
            }
        } symbols: {
            AlbumItemCount(picCount: picCount, albumCount: albumCount)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                .tag("itemCount")
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: length.map { $0 * 1.16 }, height: length.map { $0 * 1.16 })
        .padding(length.map { $0 * -0.08 } ?? 0)
        .transition(.opacity.animation(.smooth.speed(2)))
    }

    private func drawRotatedCard(
        context: GraphicsContext,
        size: CGSize,
        image: Image,
        cardW: CGFloat,
        cardH: CGFloat,
        cornerRadius: CGFloat,
        angle: Angle,
        shadowColor: Color,
        shadowRadius: CGFloat,
        shadowY: CGFloat
    ) {
        let cardRect = CGRect(
            x: (size.width - cardW) / 2,
            y: (size.height - cardH) / 2,
            width: cardW,
            height: cardH
        )
        let cardPath = Path(
            roundedRect: cardRect,
            cornerRadius: cornerRadius,
            style: .continuous
        )
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        var ctx = context
        ctx.addFilter(.shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY))
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)
        ctx.translateBy(x: -center.x, y: -center.y)
        ctx.drawLayer { inner in
            inner.clip(to: cardPath)
            let resolved = inner.resolve(image)
            let srcSize = resolved.size
            let scale = max(cardW / srcSize.width, cardH / srcSize.height)
            let drawW = srcSize.width * scale
            let drawH = srcSize.height * scale
            let drawRect = CGRect(
                x: cardRect.midX - drawW / 2,
                y: cardRect.midY - drawH / 2,
                width: drawW,
                height: drawH
            )
            inner.draw(resolved, in: drawRect)
        }
    }

}

struct AlbumCoverFill: View {

    var name: String
    var image: Image?

    var body: some View {
        if let image {
            Color.clear
                .overlay {
                    image
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else {
            let colors = Color.gradient(from: name)
            LinearGradient(colors: [colors.primary, colors.secondary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct AlbumFlatCover: View {

    var name: String
    var length: CGFloat?
    var image: Image?
    var cornerRadius: CGFloat = 10.0
    var isDownloading: Bool = false

    var body: some View {
        Color.clear
            .aspectRatio(1.0, contentMode: .fit)
            .frame(width: length)
            .overlay {
                AlbumCoverFill(name: name, image: image)
            }
            .overlay {
                if isDownloading {
                    Color.black.opacity(0.3)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
            }
            .transition(.opacity.animation(.smooth.speed(2)))
    }
}

struct AlbumPeekCover: View {

    var name: String
    var length: CGFloat?
    var primaryImage: Image?
    var secondaryImage: Image?
    var tertiaryImage: Image?
    var isDownloading: Bool = false

    static let peekHeight: CGFloat = 10.0

    var body: some View {
        AlbumFlatCover(name: name, image: primaryImage, isDownloading: isDownloading)
            .frame(width: length)
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1.0)
            .background(alignment: .top) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .top) {
                        if let tertiaryImage {
                            backCard(tertiaryImage, width: width * 0.72, height: width)
                                .offset(y: -Self.peekHeight)
                                .opacity(0.7)
                        }
                        if let secondaryImage {
                            backCard(secondaryImage, width: width * 0.86, height: width)
                                .offset(y: -Self.peekHeight / 2)
                                .opacity(0.9)
                        }
                    }
                    .frame(width: width)
                }
            }
            .padding(.top, Self.peekHeight)
    }

    func backCard(_ image: Image, width: CGFloat, height: CGFloat) -> some View {
        AlbumCoverFill(name: name, image: image)
            .saturation(0.8)
            .brightness(-0.12)
            .frame(width: width, height: height)
            .clipShape(.rect(cornerRadius: 9.0, style: .continuous))
    }
}

struct AlbumMosaicCover: View {

    var name: String
    var length: CGFloat?
    var primaryImage: Image?
    var secondaryImage: Image?
    var tertiaryImage: Image?
    var isDownloading: Bool = false

    var body: some View {
        Color.clear
            .aspectRatio(1.0, contentMode: .fit)
            .frame(width: length)
            .overlay {
                HStack(spacing: 1.5) {
                    AlbumCoverFill(name: name, image: primaryImage)
                    if secondaryImage != nil {
                        VStack(spacing: 1.5) {
                            AlbumCoverFill(name: name, image: secondaryImage)
                            if tertiaryImage != nil {
                                AlbumCoverFill(name: name, image: tertiaryImage)
                            }
                        }
                    }
                }
            }
            .overlay {
                if isDownloading {
                    Color.black.opacity(0.3)
                }
            }
            .clipShape(.rect(cornerRadius: 12.0, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12.0, style: .continuous)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
            }
            .transition(.opacity.animation(.smooth.speed(2)))
    }
}
