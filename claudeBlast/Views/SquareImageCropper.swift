// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SquareImageCropper.swift
//  claudeBlast
//
//  Pinch/pan square crop for caregiver tile photos. Tiles render square, so the
//  caregiver picks the 1:1 region that reads best at tile size.
//
//  Design notes (lessons from a prior cropper that fought orientation):
//   - The source image is normalized to `.up` ONCE on appear, so every later
//     coordinate calculation is orientation-free. No re-deriving orientation at
//     crop time.
//   - ONE coordinate space throughout: the GeometryReader's `size`. The on-screen
//     image rect, the crop window, the gesture clamps, and the final pixel
//     mapping are all derived from it — no mixing in UIScreen bounds.
//   - A minimum zoom is computed so the (square) crop window is always fully
//     covered by the image; the caregiver can never crop empty/black area.
//

import SwiftUI
import UIKit

struct SquareImageCropper: View {
    let image: UIImage
    let onCrop: (UIImage) -> Void
    let onCancel: () -> Void

    /// Crop window as a fraction of the smaller view dimension.
    private let cropFactor: CGFloat = 0.85
    /// How far past the minimum-cover zoom the caregiver may pinch in.
    private let maxZoomFactor: CGFloat = 6.0

    @State private var upright: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero

    @GestureState private var gestureOffset: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let viewSize = geo.size
                let img = upright ?? image
                let geom = CropGeometry(imagePixelSize: img.pixelSize,
                                        viewSize: viewSize,
                                        cropFactor: cropFactor)

                ZStack {
                    Color.black.ignoresSafeArea()

                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale * gestureScale)
                        .offset(x: offset.width + gestureOffset.width,
                                y: offset.height + gestureOffset.height)
                        .gesture(dragGesture(geom))
                        .simultaneousGesture(magnifyGesture(geom))
                        .highPriorityGesture(
                            TapGesture(count: 2).onEnded {
                                withAnimation { resetTo(geom) }
                            }
                        )

                    // Dim outside the crop window + a crisp border, drawn in the
                    // SAME frame (this GeometryReader) that the image layout and
                    // crop math use, so the window and the captured pixels align.
                    cropOverlay(cropSide: geom.cropSide)
                }
                .onAppear {
                    if upright == nil { upright = image.normalizedUp() }
                    // Recompute against the upright image's geometry.
                    let g = CropGeometry(imagePixelSize: (upright ?? image).pixelSize,
                                         viewSize: viewSize,
                                         cropFactor: cropFactor)
                    resetTo(g)
                }
                .navigationTitle("Adjust Crop")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use Photo") {
                            onCrop(cropped(img, geom))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Gestures

    private func dragGesture(_ geom: CropGeometry) -> some Gesture {
        DragGesture()
            .updating($gestureOffset) { value, state, _ in state = value.translation }
            .onEnded { value in
                let combined = CGSize(width: offset.width + value.translation.width,
                                      height: offset.height + value.translation.height)
                offset = geom.clampOffset(combined, scale: scale)
            }
    }

    private func magnifyGesture(_ geom: CropGeometry) -> some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in state = value }
            .onEnded { value in
                scale = geom.clampScale(scale * value, maxZoomFactor: maxZoomFactor)
                offset = geom.clampOffset(offset, scale: scale)
            }
    }

    private func resetTo(_ geom: CropGeometry) {
        scale = geom.minScale
        offset = .zero
    }

    /// Centered dim + square border. Centered by the enclosing ZStack, so it
    /// shares the GeometryReader frame used by `CropGeometry` — no separate
    /// GeometryReader, no `ignoresSafeArea` (that was the offset bug). The dim
    /// uses an even-odd fill (outer rect minus the square hole) rather than a
    /// blend-mode mask, avoiding the compositing path that logs the spurious
    /// "UIColor … far outside the expected range" warning.
    @ViewBuilder
    private func cropOverlay(cropSide: CGFloat) -> some View {
        CropHole(cropSide: cropSide, cornerRadius: 12)
            .fill(.black.opacity(0.5), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(.white, lineWidth: 2)
            .frame(width: cropSide, height: cropSide)
            .allowsHitTesting(false)
    }

    // MARK: - Crop

    /// Map the on-screen crop window into upright-image pixel space and crop.
    private func cropped(_ img: UIImage, _ geom: CropGeometry) -> UIImage {
        guard let cg = img.cgImage else { return img }
        let rect = geom.cropRectInPixels(scale: scale, offset: offset)
            .intersection(CGRect(origin: .zero, size: img.pixelSize))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1,
              let cropped = cg.cropping(to: rect) else { return img }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }
}

// MARK: - Crop geometry (pure math, no view state)

/// All crop math in one place, derived solely from the image pixel size, the
/// view size, and the crop factor. `scale` here means the SwiftUI `scaleEffect`
/// applied on top of `.scaledToFit` — `minScale` is the zoom at which the
/// square crop window is exactly covered by the image's smaller fitted edge.
private struct CropGeometry {
    let imagePixelSize: CGSize
    let viewSize: CGSize
    let cropSide: CGFloat
    /// Fitted on-screen image size at scaleEffect == 1 (`.scaledToFit`).
    let baseSize: CGSize

    init(imagePixelSize: CGSize, viewSize: CGSize, cropFactor: CGFloat) {
        self.imagePixelSize = imagePixelSize
        self.viewSize = viewSize
        self.cropSide = min(viewSize.width, viewSize.height) * cropFactor
        let fit = min(viewSize.width / max(imagePixelSize.width, 1),
                      viewSize.height / max(imagePixelSize.height, 1))
        self.baseSize = CGSize(width: imagePixelSize.width * fit,
                               height: imagePixelSize.height * fit)
    }

    /// Smallest scaleEffect that keeps both fitted dimensions ≥ the crop window,
    /// so the crop square is always fully covered by image pixels.
    var minScale: CGFloat {
        let smallerFitted = min(baseSize.width, baseSize.height)
        guard smallerFitted > 0 else { return 1 }
        return max(1, cropSide / smallerFitted)
    }

    func clampScale(_ s: CGFloat, maxZoomFactor: CGFloat) -> CGFloat {
        min(max(s, minScale), minScale * maxZoomFactor)
    }

    /// On-screen drawn image size at the given scaleEffect.
    private func drawSize(_ scale: CGFloat) -> CGSize {
        CGSize(width: baseSize.width * scale, height: baseSize.height * scale)
    }

    /// Clamp pan so the crop window never leaves the drawn image.
    func clampOffset(_ offset: CGSize, scale: CGFloat) -> CGSize {
        let draw = drawSize(scale)
        let maxX = max(0, (draw.width - cropSide) / 2)
        let maxY = max(0, (draw.height - cropSide) / 2)
        return CGSize(width: offset.width.clampedTo(-maxX...maxX),
                      height: offset.height.clampedTo(-maxY...maxY))
    }

    /// Crop window in upright-image PIXEL coordinates for the given transform.
    func cropRectInPixels(scale: CGFloat, offset: CGSize) -> CGRect {
        let draw = drawSize(scale)
        // scaleEffect scales about center, then offset translates.
        let drawOrigin = CGPoint(
            x: (viewSize.width - draw.width) / 2 + offset.width,
            y: (viewSize.height - draw.height) / 2 + offset.height
        )
        let cropOrigin = CGPoint(x: (viewSize.width - cropSide) / 2,
                                 y: (viewSize.height - cropSide) / 2)
        // Uniform screen→pixel factor (draw preserves the image aspect ratio).
        let pxPerPoint = imagePixelSize.width / max(draw.width, 1)
        return CGRect(
            x: (cropOrigin.x - drawOrigin.x) * pxPerPoint,
            y: (cropOrigin.y - drawOrigin.y) * pxPerPoint,
            width: cropSide * pxPerPoint,
            height: cropSide * pxPerPoint
        ).integral
    }
}

// MARK: - Crop window shape

/// Full-bounds rectangle with a centered rounded-square hole. Filled even-odd to
/// dim everything outside the crop window in one pass (no blend-mode compositing).
private struct CropHole: Shape {
    let cropSide: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let hole = CGRect(x: rect.midX - cropSide / 2,
                          y: rect.midY - cropSide / 2,
                          width: cropSide, height: cropSide)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        return path
    }
}

// MARK: - Helpers

private extension Comparable {
    func clampedTo(_ limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension UIImage {
    /// Pixel dimensions (size in points × scale), independent of orientation
    /// metadata once the image has been normalized.
    var pixelSize: CGSize {
        guard let cg = cgImage else {
            return CGSize(width: size.width * scale, height: size.height * scale)
        }
        return CGSize(width: cg.width, height: cg.height)
    }

    /// Return a copy whose pixels are baked to `.up` orientation. No-op if
    /// already upright. Renderer-based (no deprecated UIGraphics context).
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
