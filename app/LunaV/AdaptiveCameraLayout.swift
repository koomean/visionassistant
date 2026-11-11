import SwiftUI

/// Keeps the camera and its single set of controls together as the window moves
/// between displays. State, sessions and models remain owned by CameraScreen.
struct AdaptiveCameraLayout<Media: View, Controls: View>: View {
    private let media: Media
    private let controls: (CGSize) -> Controls
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(@ViewBuilder media: () -> Media, @ViewBuilder controls: @escaping (CGSize) -> Controls) {
        self.media = media()
        self.controls = controls
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if #available(iOS 27.1, *) {
                    ArrangementView {
                        GeometryReader { pane in controls(pane.size) }
                    } secondary: {
                        media.clipped()
                    }
                    .arrangementViewStyle(CameraArrangementStyle())
                } else {
                    // Earlier supported iOS versions have no folding displays.
                    let wide = horizontalSizeClass == .regular && proxy.size.width > proxy.size.height
                    let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(ZStackLayout())
                    layout {
                        GeometryReader { pane in
                            media.frame(width: pane.size.width, height: pane.size.height).clipped()
                        }
                        GeometryReader { pane in
                            controls(pane.size).frame(width: pane.size.width, height: pane.size.height)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            #if DEBUG && targetEnvironment(simulator)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cameraAdaptiveLayout")
            .accessibilityValue(diagnosticValue(proxy))
            #endif
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    private func diagnosticValue(_ proxy: GeometryProxy) -> String {
        let divisionCount: Int
        if #available(iOS 27.1, *) { divisionCount = proxy.reservedRegions(kind: .division).count }
        else { divisionCount = 0 }
        let mode = divisionCount > 0 ? "fold" : horizontalSizeClass == .regular && proxy.size.width > proxy.size.height ? "split" : "overlay"
        return "mode=\(mode);divisionCount=\(divisionCount);width=\(Int(proxy.size.width));height=\(Int(proxy.size.height))"
    }
    #endif

}

@available(iOS 27.1, *)
private struct CameraArrangementStyle: ArrangementViewStyle {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            let hasFold = !proxy.reservedRegions(kind: .division).isEmpty
            if horizontalSizeClass == .regular && proxy.size.width > proxy.size.height && !hasFold {
                ArrangementView {
                    configuration.secondary
                } secondary: {
                    configuration.primary
                }
                .arrangementViewStyle(.split.axes(.horizontal))
            } else {
                // The system places controls after the fold when held like a
                // book, or below it when resting on a table. On a flat compact
                // display, controls overlay the full camera just as before.
                ArrangementView(configuration)
                    .arrangementViewStyle(.overlay)
            }
        }
    }
}

/// Photo selection must use one uninterrupted image coordinate space. Native
/// arrangements place that image above/beside scrollable tools when folded.
struct AdaptivePhotoToolsLayout<Photo: View, Tools: View>: View {
    private let photo: Photo
    private let tools: Tools

    init(@ViewBuilder photo: () -> Photo, @ViewBuilder tools: () -> Tools) {
        self.photo = photo()
        self.tools = tools()
    }

    var body: some View {
        if #available(iOS 27.1, *) {
            ArrangementView {
                photo.clipped()
            } secondary: {
                tools
                    .splitArrangementLayoutRatio(minHorizontal: 0.3, idealHorizontal: 0.4, maxHorizontal: 0.5,
                                                 minVertical: 0.25, idealVertical: 0.35, maxVertical: 0.5)
            }
            .arrangementViewStyle(.split)
        } else {
            VStack(spacing: 16) {
                photo
                tools.frame(maxHeight: 240)
            }
        }
    }
}

extension View {
    /// Use around custom centered scroll content inside a native navigation
    /// container. Native bars remain managed by the system outside this frame.
    func foldAwareReadable() -> some View { modifier(FoldAwareReadableModifier()) }
}

private struct FoldAwareReadableModifier: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let pane = readablePane(in: proxy, bounds: bounds)
            content
                .frame(width: pane.width, height: pane.height)
                .position(x: pane.midX, y: pane.midY)
        }
    }

    private func readablePane(in proxy: GeometryProxy, bounds: CGRect) -> CGRect {
        guard #available(iOS 27.1, *) else { return bounds }
        return proxy.reservedRegions(kind: .division).reduce(bounds) { available, region in
            let margins = region.margins
            let exclusion = CGRect(x: region.frame.minX - margins.leading,
                                   y: region.frame.minY - margins.top,
                                   width: region.frame.width + margins.leading + margins.trailing,
                                   height: region.frame.height + margins.top + margins.bottom)
            return FoldReadableGeometry.preferredPane(in: available, avoiding: exclusion)
        }
    }
}

/// Pure geometry used by the single-column secondary screens. With equally
/// sized panes, trailing/bottom keeps controls on the stable/reachable side.
enum FoldReadableGeometry {
    static func preferredPane(in bounds: CGRect, avoiding exclusion: CGRect) -> CGRect {
        let fold = bounds.intersection(exclusion)
        guard !exclusion.isEmpty, !fold.isNull, !fold.isEmpty, bounds.width > 0, bounds.height > 0 else { return bounds }
        let before: CGRect
        let after: CGRect
        if fold.height >= fold.width {
            before = CGRect(x: bounds.minX, y: bounds.minY,
                            width: max(0, fold.minX - bounds.minX), height: bounds.height)
            after = CGRect(x: fold.maxX, y: bounds.minY,
                           width: max(0, bounds.maxX - fold.maxX), height: bounds.height)
        } else {
            before = CGRect(x: bounds.minX, y: bounds.minY,
                            width: bounds.width, height: max(0, fold.minY - bounds.minY))
            after = CGRect(x: bounds.minX, y: fold.maxY,
                           width: bounds.width, height: max(0, bounds.maxY - fold.maxY))
        }
        let preferred = before.width * before.height > after.width * after.height ? before : after
        return preferred.width > 0 && preferred.height > 0 ? preferred : bounds
    }
}
