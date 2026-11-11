import SwiftUI

/// The website's short LunaVision → LunaV sequence, rendered with native vectors.
/// Model preparation belongs to the presenting screen and starts independently.
struct LunaIntroView: View {
    let status: String
    let destination: CGRect?
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appLanguage) private var appLanguage
    @State private var appeared = false
    @State private var penVisible = false
    @State private var inkProgress: CGFloat = 0
    @State private var collapse: CGFloat = 0
    @State private var alignment: CGFloat = 0
    @State private var docking: CGFloat = 0
    @State private var curtain: CGFloat = 1
    @State private var widths: [String: CGFloat] = [:]
    @State private var hasFinished = false
    @State private var initialSize: CGSize?

    private var usesReducedMotion: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return reduceMotion || ProcessInfo.processInfo.arguments.contains("--uitesting-reduce-motion")
        #else
        return reduceMotion
        #endif
    }

    init(status: String, destination: CGRect? = nil, onFinished: @escaping () -> Void) {
        self.status = status
        self.destination = destination
        self.onFinished = onFinished
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let fontSize = min(48, max(32, (size.width - 48) / 6.8))
            let finalScale = 25 / fontSize
            let stem = widths["stem"] ?? fontSize * 2.55
            let dot = widths["dot"] ?? fontSize * 0.22
            let retired = widths["retired"] ?? fontSize * 1.8
            let wordWidth = stem + retired * (1 - collapse) + dot * collapse
            let finalWordWidth = (stem + dot) * finalScale
            let center = CGPoint(x: size.width / 2, y: size.height * 0.47)
            let inlineMoon = 30 / finalScale
            let inlineGap = 10 / finalScale
            let inlineWidth = inlineMoon + inlineGap + wordWidth
            // The parent resolves the header anchor in this same full-window
            // overlay space; no global/local safe-area conversion is needed.
            let target = destination.flatMap { rect in
                rect.width > 0 && rect.height > 0 ? rect : nil
            }
                ?? CGRect(x: 22, y: geometry.safeAreaInsets.top + 8, width: 40 + finalWordWidth, height: 48)
            let finalMoon = CGPoint(x: target.minX + 15, y: target.midY)
            let finalWord = CGPoint(x: target.minX + 40 + finalWordWidth / 2, y: target.midY)
            let alignedMoon = CGPoint(x: center.x - inlineWidth / 2 + inlineMoon / 2, y: center.y)
            let alignedWord = CGPoint(x: center.x - inlineWidth / 2 + inlineMoon + inlineGap + wordWidth / 2, y: center.y)

            ZStack {
                backdrop(size: size, center: center).opacity(curtain)

                if usesReducedMotion {
                    HStack(spacing: 14) {
                        Image("BrandMark").resizable().scaledToFit().frame(width: 52, height: 52)
                        Text("\(Text("LunaV").foregroundColor(LunaTheme.paper))\(Text(".").foregroundColor(LunaTheme.gold))")
                            .font(LunaTheme.brandFont(size: 42, weight: .semibold))
                            .tracking(-2.52)
                    }
                    .position(center)
                    .accessibilityHidden(true)
                } else {
                    Image("IntroMoon")
                        .resizable().scaledToFit()
                        .frame(width: mix(72, inlineMoon, alignment), height: mix(72, inlineMoon, alignment))
                        .scaleEffect(mix(1, finalScale, docking))
                        .position(mix(mix(CGPoint(x: center.x, y: center.y - 56), alignedMoon, alignment), finalMoon, docking))
                        .opacity(appeared ? 1 : 0)
                        .accessibilityHidden(true)

                    wordmark(fontSize: fontSize, retiredWidth: retired, dotWidth: dot)
                        .scaleEffect(mix(1, finalScale, docking))
                        .position(mix(mix(CGPoint(x: center.x, y: center.y + 39), alignedWord, alignment), finalWord, docking))
                        .offset(y: appeared ? 0 : 10)
                        .opacity(appeared ? 1 : 0)
                        .accessibilityHidden(true)
                }

            }
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    Text("กำลังเตรียมพร้อมให้คุณ")
                        .font(LunaTheme.font(.subheadline, weight: .medium))
                        .foregroundStyle(LunaTheme.paper)
                    Text(appLanguage.text(status))
                        .font(LunaTheme.font(.footnote))
                        .foregroundStyle(LunaTheme.muted)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("launchPreparationStatus")
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 440)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20) + 48)
                .opacity(curtain)
            }
            .onPreferenceChange(IntroTextWidths.self) { widths = $0 }
            .onAppear { initialSize = size }
            .onChange(of: size) { _, next in
                if let initialSize, initialSize != next { finish() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launchIntro")
        .accessibilityValue(appLanguage.text(status))
        .task { await animateIntroduction() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { finish() }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { finish() }
        }
    }

    private func backdrop(size: CGSize, center: CGPoint) -> some View {
        ZStack {
            LunaTheme.night
            RadialGradient(colors: [LunaTheme.blue.opacity(0.08), .clear], center: .center,
                           startRadius: 0, endRadius: min(size.width * 0.7, 450))
            let diameter = min(size.width * 0.88, 510)
            ZStack {
                Circle().stroke(LunaTheme.blue.opacity(0.1), lineWidth: 1)
                Circle().inset(by: 20).stroke(LunaTheme.blue.opacity(0.055), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                Circle().fill(LunaTheme.gold).frame(width: 5, height: 5)
                    .offset(x: diameter * 0.35, y: -diameter * 0.35)
            }
            .frame(width: diameter, height: diameter)
            .position(center)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func wordmark(fontSize: CGFloat, retiredWidth: CGFloat, dotWidth: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            measuredText("LunaV", key: "stem", fontSize: fontSize)
            measuredText("ision", key: "retired", fontSize: fontSize)
                .overlay {
                    GeometryReader { geometry in
                        let rect = CGRect(x: 0, y: geometry.size.height * 0.3,
                                          width: geometry.size.width, height: geometry.size.height * 0.55)
                        ZStack(alignment: .topLeading) {
                            IntroInk(progress: inkProgress, writingRect: rect)
                                .stroke(Color(red: 238 / 255, green: 98 / 255, blue: 91 / 255),
                                        style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                            Image("IntroPen").resizable().scaledToFit()
                                .frame(width: 18, height: 54)
                                .rotationEffect(.degrees(30), anchor: .bottom)
                                .offset(x: -9, y: -54)
                                .modifier(IntroPenPosition(progress: inkProgress, writingRect: rect))
                                .opacity(penVisible ? 1 : 0)
                        }
                    }
                }
                .frame(width: retiredWidth * (1 - collapse), alignment: .leading)
                .blur(radius: 5 * collapse)
                .opacity(1 - collapse)
            measuredText(".", key: "dot", fontSize: fontSize, color: LunaTheme.gold)
                .frame(width: dotWidth * collapse)
                .opacity(collapse)
        }
        .fixedSize()
    }

    private func measuredText(_ value: String, key: String, fontSize: CGFloat, color: Color? = nil) -> some View {
        Text(verbatim: value)
            .font(LunaTheme.brandFont(size: fontSize, weight: .semibold))
            .tracking(-fontSize * 0.06)
            .foregroundStyle(color ?? LunaTheme.paper)
            .fixedSize()
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: IntroTextWidths.self, value: [key: geometry.size.width])
                }
            }
    }

    private func animateIntroduction() async {
        // Every suspension is cancellable. The task never owns or awaits a model.
        do {
            if usesReducedMotion {
                try await Task.sleep(for: .milliseconds(200))
                finish()
                return
            }
            try Task.checkCancellation()
            withAnimation(.easeOut(duration: 0.38)) { appeared = true }
            try await Task.sleep(for: .milliseconds(810))
            withAnimation(.easeOut(duration: 0.18)) { penVisible = true }
            try await Task.sleep(for: .milliseconds(180))
            withAnimation(.linear(duration: 0.78)) { inkProgress = 1 }
            try await Task.sleep(for: .milliseconds(780))
            withAnimation(.easeOut(duration: 0.18)) { penVisible = false }
            try await Task.sleep(for: .milliseconds(530))
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.44)) { collapse = 1 }
            try await Task.sleep(for: .milliseconds(440))
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.48)) { alignment = 1 }
            try await Task.sleep(for: .milliseconds(580))
            withAnimation(.timingCurve(0.65, 0, 0.2, 1, duration: 0.9)) { docking = 1 }
            withAnimation(.easeInOut(duration: 0.8).delay(0.1)) { curtain = 0 }
            try await Task.sleep(for: .milliseconds(900))
            finish()
        } catch {
            // Backgrounding or removing the overlay cannot leave input blocked.
            finish()
        }
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        onFinished()
    }

    private func mix(_ start: CGFloat, _ end: CGFloat, _ fraction: CGFloat) -> CGFloat {
        start + (end - start) * fraction
    }

    private func mix(_ start: CGPoint, _ end: CGPoint, _ fraction: CGFloat) -> CGPoint {
        CGPoint(x: mix(start.x, end.x, fraction), y: mix(start.y, end.y, fraction))
    }
}

private struct IntroTextWidths: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// A flattened arc-length table of the website's exact SVG quadratic wave.
/// Ink and pen share this table, so the writing tip stays on the visible stroke.
private enum IntroWave {
    static let points: [CGPoint] = {
        var result = [CGPoint(x: 2, y: 26)]
        var start = result[0]
        for index in 0..<10 {
            let control = index == 9 ? CGPoint(x: 154, y: 10)
                : CGPoint(x: start.x + 8, y: index.isMultiple(of: 2) ? 8 : 44)
            let end = index == 9 ? CGPoint(x: 158, y: 24) : CGPoint(x: start.x + 16, y: 26)
            for step in 1...24 {
                let t = CGFloat(step) / 24
                let u = 1 - t
                result.append(CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                                      y: u * u * start.y + 2 * u * t * control.y + t * t * end.y))
            }
            start = end
        }
        return result
    }()

    static let lengths: [CGFloat] = {
        var result: [CGFloat] = [0]
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            result.append(result[index - 1] + hypot(current.x - previous.x, current.y - previous.y))
        }
        return result
    }()

    static func location(_ progress: CGFloat) -> (index: Int, point: CGPoint) {
        let distance = min(1, max(0, progress)) * (lengths.last ?? 0)
        var low = 0
        var high = lengths.count - 1
        while low < high {
            let middle = (low + high) / 2
            if lengths[middle] < distance { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return (0, points[0]) }
        let interval = lengths[low] - lengths[low - 1]
        let fraction = interval > 0 ? (distance - lengths[low - 1]) / interval : 0
        let start = points[low - 1]
        let end = points[low]
        return (low, CGPoint(x: start.x + (end.x - start.x) * fraction,
                             y: start.y + (end.y - start.y) * fraction))
    }

    static func project(_ point: CGPoint, into rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x / 160 * rect.width, y: rect.minY + point.y / 50 * rect.height)
    }
}

private struct IntroInk: Shape {
    var progress: CGFloat
    let writingRect: CGRect
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard progress > 0 else { return Path() }
        let location = IntroWave.location(progress)
        var path = Path()
        path.move(to: IntroWave.project(IntroWave.points[0], into: writingRect))
        if location.index > 0 {
            for point in IntroWave.points[1..<location.index] { path.addLine(to: IntroWave.project(point, into: writingRect)) }
        }
        path.addLine(to: IntroWave.project(location.point, into: writingRect))
        return path
    }
}

private struct IntroPenPosition: GeometryEffect {
    var progress: CGFloat
    let writingRect: CGRect
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let point = IntroWave.project(IntroWave.location(progress).point, into: writingRect)
        return ProjectionTransform(CGAffineTransform(translationX: point.x, y: point.y))
    }
}
