import PhotosUI
import SwiftUI

private struct LunaBrandFrameKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

enum CameraQuestionPreference {
    static let reusePhotoKey = "lunav.voice.reuse-photo"
}

struct CameraScreen: View {
    @State private var camera: CameraController
    @State private var chat: ChatViewModel
    @State private var voice: VoiceCameraFlow
    @State private var preparation: ModelPreparation
    @State private var preparationStartedAt: Date?
    @State private var obstacleThermalPaused = ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical
    @State private var selectedPhoto: PhotosPickerItem?
    @AppStorage(CameraQuestionPreference.reusePhotoKey) private var reusePhotoOnHold = false
    @State private var showSettings = false
    @State private var pendingRoute: SettingsRoute?
    @State private var conversationDetent: PresentationDetent = .large
    @State private var lifecycleTask: Task<Void, Never>?
    @State private var lifecycleRevision = UUID()
    @State private var cameraLifecycleBusy = true
    @State private var shutterPressStartedAt: ContinuousClock.Instant?
    @State private var lastMessageBeforeVoice: ChatMessage.ID?
    @State private var showsIntroduction = LunaLaunchPolicy.showsIntroduction(arguments: ProcessInfo.processInfo.arguments)
    #if DEBUG && targetEnvironment(simulator)
    @State private var uiTestVoice: VoiceCameraUITestBoundary?
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appLanguage) private var appLanguage

    init() {
        let camera = CameraController()
        let chat = ChatViewModel(answerSpeech: AnswerSpeechPlayer())
        _camera = State(initialValue: camera)
        _chat = State(initialValue: chat)
        let preparation = ModelPreparation(chat: chat)
        _preparation = State(initialValue: preparation)
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--uitesting-voice") {
            let boundary = VoiceCameraUITestBoundary(
                slow: ProcessInfo.processInfo.arguments.contains("--uitesting-voice-slow-asr"))
            _uiTestVoice = State(initialValue: boundary)
            _voice = State(initialValue: boundary.makeFlow(chat: chat))
            return
        }
        #endif
        _voice = State(initialValue: VoiceCameraFlow(camera: camera, chat: chat, speech: preparation.speech))
    }

    var body: some View {
        AdaptiveCameraLayout {
            cameraCanvas
        } controls: { size in
            VStack(spacing: 0) {
                header.layoutPriority(1)
                GeometryReader { readout in
                    let gap: CGFloat = size.height < 480 ? 8 : 16
                    let available = max(0, readout.size.height - gap)
                    VStack(spacing: 0) {
                        if !preparation.isReady {
                            ScrollView { preparationPanel }
                                .frame(maxHeight: available * (hasResponse ? 0.55 : 1))
                                .scrollBounceBehavior(.basedOnSize)
                        }
                        Spacer(minLength: 0)
                        if hasResponse {
                            responsePanel
                                .frame(maxWidth: 600)
                                .frame(maxHeight: available * (preparation.isReady ? 1 : 0.45))
                                .padding(.horizontal, 18)
                                .padding(.bottom, gap)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
                // Reserve the physical shutter's space before offering any
                // remainder to the scrollable response on a short display.
                captureControls(compact: size.height < 480).layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LunaTheme.night).preferredColorScheme(.dark)
        .foregroundStyle(LunaTheme.paper)
        .font(LunaTheme.font(.body))
        .tint(LunaTheme.gold)
        .overlayPreferenceValue(LunaBrandFrameKey.self) { headerAnchor in
            GeometryReader { overlay in
                if showsIntroduction {
                    // Resolve the header and draw the intro in the same full-window
                    // coordinate space, including the status-bar safe area.
                    LunaIntroView(status: preparation.status, destination: headerAnchor.map { overlay[$0] }) {
                        withTransaction(Transaction(animation: nil)) { showsIntroduction = false }
                    }
                    .transition(.identity)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .task {
            await enqueueLifecycle(scenePhase).value
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                do {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        await voice.cancel()
                        voice.resetPresentation()
                        await camera.stop()
                        await chat.setPhoto(data, openConversation: false)
                        if chat.photo != nil, chat.error == nil, !Task.isCancelled {
                            routeFromSettings(.conversation(.question))
                        }
                    }
                } catch { chat.error = "เปิดภาพไม่ได้ กรุณาเลือกรูปใหม่" }
                selectedPhoto = nil
            }
        }
        .onChange(of: chat.action) { _, action in
            if action != .question { conversationDetent = .large }
        }
        .task(id: obstacleMonitoringRequest) {
            let request = obstacleMonitoringRequest
            if request.active && request.configuration.enabled && camera.obstacles.isSupported && !camera.isReady {
                await camera.start()
            }
            guard !Task.isCancelled, request == obstacleMonitoringRequest else { return }
            await camera.setObstacleMonitoring(active: request.active && camera.isReady)
            guard !Task.isCancelled, request == obstacleMonitoringRequest else { return }
            if chat.photo != nil && !voice.isBusy && !camera.isCapturing && !cameraLifecycleBusy
                && (!request.configuration.enabled || !camera.obstacles.isSupported || !request.active) {
                await camera.stop()
            }
        }
        .onChange(of: camera.isReady) { _, _ in updateIdleTimer() }
        .onChange(of: chat.isWorking) { _, _ in updateIdleTimer() }
        .onChange(of: voice.isBusy) { _, _ in updateIdleTimer() }
        .onChange(of: chat.answerSpeech?.isSpeaking) { _, _ in updateIdleTimer() }
        .onChange(of: preparation.isPreparing) { _, preparing in
            preparationStartedAt = preparing ? .now : nil
            updateIdleTimer()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            _ = enqueueLifecycle(.background)
        }
        .onChange(of: scenePhase) { _, phase in
            updateIdleTimer()
            _ = enqueueLifecycle(phase)
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            chat.refreshPolicy()
            obstacleThermalPaused = ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            chat.refreshPolicy()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            MemoryWarningRecorder.record(capturing: camera.isCapturing, preparingPhoto: chat.isPreparingPhoto,
                                         answering: chat.isWorking, modelReady: preparation.isReady)
            _ = enqueueLifecycle(scenePhase, memoryPressure: true)
        }
        .sheet(isPresented: $showSettings, onDismiss: completeSettingsRoute) {
            CameraSettingsSheet(camera: camera, chat: chat, voice: voice, preparation: preparation, selectedPhoto: $selectedPhoto,
                openManual: { routeFromSettings(.conversation($0)) },
                openPerformance: { routeFromSettings(.performance) },
                useSample: useSamplePhoto)
        }
        .sheet(isPresented: $chat.showConversation) {
            ConversationSheet(chat: chat, retake: {
                Task {
                    await voice.cancel()
                    voice.resetPresentation()
                    await chat.retake()
                    await camera.start()
                }
            }, clearPresentation: { voice.resetPresentation() })
            .presentationDetents([.medium, .large], selection: $conversationDetent)
            .presentationDragIndicator(.visible)
            .presentationBackground(LunaTheme.night)
            .interactiveDismissDisabled(chat.isWorking)
        }
        .sheet(isPresented: $chat.showDetails) { PerformanceSheet(chat: chat) }
    }

    private var cameraCanvas: some View {
        ZStack {
            LunaTheme.night
            if let photo = chat.photo {
                Image(uiImage: photo).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            } else {
                CameraPreview(session: camera.session)
                if !camera.isReady {
                    VStack(spacing: 18) {
                        Image(systemName: "camera.aperture")
                            .font(.system(size: 48, weight: .ultraLight))
                        Text(appLanguage.text(camera.permissionDenied ? "เปิดสิทธิ์กล้องในเมนูตั้งค่า"
                             : camera.message ?? "กำลังเปิดกล้อง…"))
                            .font(LunaTheme.font(.subheadline)).multilineTextAlignment(.center)
                            .frame(maxWidth: 270)
                        #if targetEnvironment(simulator)
                        Text("ภาพทดสอบอยู่ในเมนูตั้งค่า")
                            .font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.paper.opacity(0.5))
                        #endif
                    }.foregroundStyle(LunaTheme.paper.opacity(0.65))
                }
            }
            GeometryReader { shade in
                // The old fixed 150 + 330 pt gradients enlarged the ZStack
                // beyond a short landscape or folded pane and clipped controls.
                VStack(spacing: 0) {
                    LinearGradient(colors: [LunaTheme.night.opacity(0.72), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: min(150, shade.size.height * 0.30))
                    Spacer(minLength: 0)
                    LinearGradient(colors: [.clear, LunaTheme.night.opacity(0.96)], startPoint: .top, endPoint: .bottom)
                        .frame(height: min(330, shade.size.height * 0.56))
                }
            }.allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            LunaBrandLockup()
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("cameraTitle")
                .opacity(showsIntroduction ? 0 : 1)
                .anchorPreference(key: LunaBrandFrameKey.self, value: .bounds) { $0 }
            Spacer()
            Button {
                guard !showsIntroduction else { return }
                shutterPressStartedAt = nil
                Task {
                    await voice.cancel()
                    showSettings = true
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 48, height: 48)
                    .background(LunaTheme.deep.opacity(0.9), in: .circle)
                    .overlay { Circle().stroke(LunaTheme.line, lineWidth: 1).allowsHitTesting(false) }
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(showsIntroduction)
            .accessibilityLabel("ตั้งค่าและทดสอบระบบ")
            .accessibilityIdentifier("cameraSettings")
        }.foregroundStyle(LunaTheme.paper)
            .padding(.horizontal, 22).padding(.top, 8)
    }

    private var currentTranscript: String {
        if voice.isBusy || voice.error != nil { return voice.transcript }
        return chat.messages.last(where: { $0.isUser })?.text ?? ""
    }

    private var currentAnswer: String {
        guard voice.error == nil, voice.phase == .idle || voice.phase == .answering,
              let last = chat.messages.last, !last.isUser else { return "" }
        // The answer belongs to this voice turn only after it has been added to the chat.
        if voice.phase == .answering && last.id == lastMessageBeforeVoice { return "" }
        return last.text
    }

    private var visibleError: String? { voice.error ?? chat.error ?? preparation.speech.preparationError }

    private var hasResponse: Bool {
        !currentTranscript.isEmpty || !currentAnswer.isEmpty || chat.isWorking
            || voice.isListening || voice.phase == .transcribing || visibleError != nil
    }

    private var responsePanel: some View {
        ScrollViewReader { reader in
            ViewThatFits(in: .vertical) {
                responseContent.fixedSize(horizontal: false, vertical: true)
                ScrollView { responseContent }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
            }
            .onChange(of: currentAnswer) { _, _ in reader.scrollTo("responseBottom", anchor: .bottom) }
            .onChange(of: currentTranscript) { _, _ in reader.scrollTo("responseBottom", anchor: .bottom) }
        }
        .background(LunaTheme.deep.opacity(0.96), in: .rect(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(LunaTheme.line, lineWidth: 1) }
    }

    private var responseContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !currentTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("คุณถาม").font(LunaTheme.font(.caption).weight(.medium)).foregroundStyle(LunaTheme.paper.opacity(0.55))
                    Text(verbatim: currentTranscript).font(LunaTheme.font(.subheadline))
                        .foregroundStyle(LunaTheme.paper.opacity(0.85))
                        .accessibilityIdentifier("voiceTranscript")
                        .textSelection(.enabled)
                }
            }
            if voice.isListening && currentTranscript.isEmpty {
                HStack(spacing: 12) {
                    AudioLevelMark(level: voice.level)
                    Text("กำลังฟัง…").font(LunaTheme.font(.body)).foregroundStyle(LunaTheme.paper.opacity(0.8))
                }.accessibilityIdentifier("listeningIndicator")
            }
            if !currentAnswer.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LunaV").font(LunaTheme.font(.caption).weight(.semibold)).foregroundStyle(LunaTheme.gold)
                    Text(verbatim: currentAnswer).font(LunaTheme.font(.body)).lineSpacing(4)
                        .accessibilityIdentifier("inlineAnswer").textSelection(.enabled)
                }
            } else if chat.isWorking || voice.phase == .transcribing {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(appLanguage.text(voice.phase == .transcribing ? voice.displayStatus : chat.status))
                        .font(LunaTheme.font(.subheadline)).foregroundStyle(LunaTheme.paper.opacity(0.65))
                }
            }
            if let error = visibleError {
                Text(appLanguage.text(error)).font(LunaTheme.font(.subheadline)).foregroundStyle(LunaTheme.danger)
                    .accessibilityIdentifier("inlineError")
            }
            Color.clear.frame(height: 1).id("responseBottom")
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
    }

    private func captureControls(compact: Bool = false) -> some View {
        VStack(spacing: compact ? 8 : 18) {
            Text(appLanguage.text(instruction)).font(LunaTheme.font(.subheadline).weight(.medium))
                .foregroundStyle(LunaTheme.paper.opacity(0.85)).multilineTextAlignment(.center)
                .accessibilityIdentifier("voiceStatus")
                .frame(maxWidth: .infinity)
            ZStack {
                    Circle().stroke(LunaTheme.gold.opacity(0.9), lineWidth: 2)
                    Circle().fill(LunaTheme.paper).padding(7)
                    if voice.isListening {
                        Image(systemName: "mic.fill").font(.system(size: 28, weight: .semibold)).foregroundStyle(LunaTheme.danger)
                    } else if voice.isBusy || chat.isWorking {
                        Image(systemName: "xmark").font(.system(size: 24, weight: .semibold)).foregroundStyle(LunaTheme.night)
                    }
                ShutterTouchSurface(isEnabled: !shutterDisabled, isObscured: showsIntroduction,
                    isBusy: voice.isBusy || chat.isWorking,
                    isListening: voice.isListening,
                    pressBegan: shutterPressed,
                    pressEnded: shutterReleased,
                    pressCancelled: shutterCancelled,
                    activated: shutterTapped,
                    startAccessibleVoice: { beginVoiceQuestion(reusingCurrentPhoto: shouldReusePhoto) },
                    startAccessibleFollowUp: hasReusablePhoto && !shouldReusePhoto ? {
                        beginVoiceQuestion(reusingCurrentPhoto: true)
                    } : nil,
                    finishAccessibleVoice: { voice.finishVoiceQuestion() })
            }.frame(width: 88, height: 88).contentShape(.circle)
            .opacity(shutterDisabled ? 0.35 : 1)
            if camera.obstacles.configuration.enabled && camera.obstacles.isSupported {
                Text(appLanguage.text(obstacleStatusDescription(camera.obstacles)))
                    .font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.gold)
                    .multilineTextAlignment(.center).accessibilityIdentifier("obstacleLiveStatus")
            }
            Text(appLanguage.text(captureProvenance)).font(LunaTheme.font(.caption2)).foregroundStyle(LunaTheme.paper.opacity(0.45))
                .multilineTextAlignment(.center).accessibilityIdentifier("cameraDepthStatus")
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, compact ? 10 : 24)
    }

    private var instruction: String {
        if !preparation.isReady { return preparation.status }
        if voice.isBusy { return voice.displayStatus }
        if chat.isWorking { return chat.status }
        if chat.answerSpeech?.isSpeaking == true { return "กำลังอ่านคำตอบ · กดค้างเพื่อถามใหม่" }
        return shouldReusePhoto ? "กดค้างเพื่อถามต่อจากภาพเดิม · แตะเพื่อถ่ายใหม่"
            : "กดค้างเพื่อถาม · แตะเพื่อถ่าย"
    }

    private var hasReusablePhoto: Bool { chat.photo != nil && chat.photoURL != nil }
    private var shouldReusePhoto: Bool { reusePhotoOnHold && hasReusablePhoto }

    private var captureProvenance: String {
        let provenance: String
        if chat.photo != nil {
            if let depth = chat.depth {
                provenance = "ภาพและ\(depth.depthSource.isEstimated ? "ระยะประมาณ" : "ระยะ") \(depth.depthSource.title) จากตอนถ่าย · ประมวลผลบนเครื่อง"
            } else { provenance = "ภาพจากตอนถ่าย · ประมวลผลบนเครื่อง" }
        } else {
            provenance = (preparation.needsMonocularDepth ? "Depth Anything 3 · ระยะประมาณจากกล้อง" : camera.depthMode.title)
                + " · ประมวลผลบนเครื่อง"
        }
        #if DEBUG && targetEnvironment(simulator)
        if let uiTestVoice {
            let hold = provenance + " · simulated hold: \(uiTestVoice.heldMilliseconds) ms"
            return ProcessInfo.processInfo.arguments.contains("--uitesting-capture-count")
                ? hold + " · captures: \(uiTestVoice.captureCount)" : hold
        }
        #endif
        return provenance
    }

    private var shutterDisabled: Bool {
        if showsIntroduction { return true }
        // The same control remains reachable for cancelling a slow decode or
        // answer. Disabling it during work previously trapped the interaction.
        if voice.isBusy || chat.isWorking { return false }
        if !preparation.isReady { return true }
        if chat.isPreparingPhoto || camera.isCapturing { return true }
        #if DEBUG && targetEnvironment(simulator)
        if uiTestVoice != nil { return false }
        #endif
        #if targetEnvironment(simulator)
        return true
        #else
        return !camera.isReady && chat.photo == nil
        #endif
    }

    private func shutterTapped() {
        if voice.isBusy || chat.isWorking {
            Task { await voice.cancel(); chat.stop() }
        } else { voice.captureOnly() }
    }

    private func shutterPressed() {
        guard shutterPressStartedAt == nil else { return }
        if voice.isBusy || chat.isWorking {
            Task { await voice.cancel(); chat.stop() }
            return
        }
        shutterPressStartedAt = ContinuousClock.now
        beginVoiceQuestion(reusingCurrentPhoto: shouldReusePhoto)
    }

    private func beginVoiceQuestion(reusingCurrentPhoto: Bool) {
        guard !shutterDisabled, !voice.isBusy, !chat.isWorking else { return }
        lastMessageBeforeVoice = chat.messages.last?.id
        voice.beginVoiceQuestion(reusingCurrentPhoto: reusingCurrentPhoto)
    }

    private func shutterReleased() {
        guard let started = shutterPressStartedAt else { return }
        shutterPressStartedAt = nil
        if started.duration(to: .now) >= VoiceCameraFlow.minimumVoiceHoldDuration { voice.finishVoiceQuestion() }
        else { voice.finishCaptureOnlyPress() }
    }

    private func shutterCancelled() {
        guard shutterPressStartedAt != nil else { return }
        shutterPressStartedAt = nil
        Task { await voice.cancel() }
    }

    private struct ObstacleMonitoringRequest: Equatable {
        let active: Bool
        let configuration: ObstacleWarningConfiguration
        let cameraReady: Bool
    }

    private var obstacleMonitoringRequest: ObstacleMonitoringRequest {
        ObstacleMonitoringRequest(
            active: scenePhase == .active
                && !camera.isCapturing && !voice.isBusy && !chat.isWorking
                && !chat.isPreparingPhoto && !preparation.isPreparing && !showsIntroduction
                && !obstacleThermalPaused && !cameraLifecycleBusy,
            configuration: camera.obstacles.configuration, cameraReady: camera.isReady)
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && (preparation.isPreparing || camera.isReady || chat.isWorking || voice.isBusy || chat.answerSpeech?.isSpeaking == true)
    }

    /// Foreground startup waits for earlier teardown, even if that teardown was
    /// superseded while joining an in-flight capture or speech decode.
    @discardableResult
    private func enqueueLifecycle(_ phase: ScenePhase, memoryPressure: Bool = false) -> Task<Void, Never> {
        if !memoryPressure && (ProcessInfo.processInfo.arguments.contains("--validate-answer-speech") || ProcessInfo.processInfo.arguments.contains("--validate-memory")) { return Task {} }
        let previous = lifecycleTask
        previous?.cancel()
        let revision = UUID()
        lifecycleRevision = revision
        cameraLifecycleBusy = true
        // Stop microphone capture immediately; camera cleanup remains ordered.
        let cancelVoice: Task<Void, Never>? = phase == .background || memoryPressure
            ? Task { await voice.cancel() } : nil
        if phase == .background || memoryPressure { shutterPressStartedAt = nil; preparation.cancelPreparation() }
        let next = Task { @MainActor in
            defer {
                if lifecycleRevision == revision { cameraLifecycleBusy = false }
            }
            await previous?.value
            if memoryPressure {
                await cancelVoice?.value
                await camera.stop()
                await preparation.memoryWarning()
            } else if phase == .background {
                await cancelVoice?.value
                await camera.stop()
                await preparation.suspend()
                return
            }
            guard !Task.isCancelled, lifecycleRevision == revision,
                  phase == .active, scenePhase == .active else { return }
            chat.answerSpeech?.prepare()
            let models = Task { await preparation.prepare() }
            await withTaskCancellationHandler {
                if chat.photo == nil || (camera.obstacles.configuration.enabled && camera.obstacles.isSupported) { await camera.start() }
                await models.value
            } onCancel: {
                models.cancel()
            }
        }
        lifecycleTask = next
        return next
    }

    private var preparationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if preparation.isPreparing { ProgressView().controlSize(.small) }
                Text(appLanguage.text(preparation.status)).font(LunaTheme.font(.subheadline).weight(.medium))
            }
            if preparation.isPreparing {
                ProgressView(value: Double(preparation.completedStages), total: Double(preparation.stageCount)).tint(LunaTheme.gold)
                if let preparationStartedAt {
                    HStack {
                        Text("เวลาที่ใช้เตรียม")
                        Spacer()
                        Text(preparationStartedAt, style: .timer).monospacedDigit()
                    }.font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.muted)
                }
                Text("เปิดครั้งแรกบนเครื่องนี้อาจใช้เวลาหลายนาที แอพจะลองใหม่อัตโนมัติหากเตรียมไม่สำเร็จ")
                    .font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.muted)
            }
            if let error = preparation.error {
                Text(appLanguage.text(error)).font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.danger)
                Button("เตรียมโมเดลอีกครั้ง") { Task { await preparation.prepare() } }
                    .accessibilityIdentifier("retryModelPreparation")
            }
        }.padding(18).frame(maxWidth: 500, alignment: .leading)
            .background(LunaTheme.deep, in: .rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(LunaTheme.line, lineWidth: 1) }
            .padding(.horizontal, 22).padding(.top, 18)
            .accessibilityIdentifier("modelPreparation")
    }

    private enum SettingsRoute {
        case conversation(PhotoAction), performance
    }

    private func routeFromSettings(_ route: SettingsRoute) {
        pendingRoute = route
        if showSettings { showSettings = false }
        else { completeSettingsRoute() }
    }

    private func completeSettingsRoute() {
        guard let route = pendingRoute else { return }
        pendingRoute = nil
        switch route {
        case .conversation(let action):
            chat.action = action
            conversationDetent = .large
            chat.showConversation = true
        case .performance: chat.showDetails = true
        }
    }

    private func useSamplePhoto() {
        #if targetEnvironment(simulator)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 768, height: 768))
        let image = renderer.image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 768, height: 768))
            UIColor.systemRed.setFill(); context.cgContext.fillEllipse(in: CGRect(x: 95, y: 145, width: 230, height: 230))
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 440, y: 420, width: 220, height: 220))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: UIColor.black]
            ("TOP: Meeting Friday at 10 AM" as NSString).draw(at: CGPoint(x: 35, y: 45), withAttributes: attributes)
            ("BOTTOM: Bring the project report" as NSString).draw(at: CGPoint(x: 35, y: 690), withAttributes: attributes)
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        Task {
            await voice.cancel()
            voice.resetPresentation()
            await chat.setPhoto(data, openConversation: false)
            if chat.photo != nil { routeFromSettings(.conversation(.question)) }
        }
        #endif
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Opt-in UI-test boundaries only: camera/microphone/ASR are simulated. The
/// production flow, physical shutter tracking and ChatViewModel submit are real.
@MainActor @Observable private final class VoiceCameraUITestBoundary {
    private let slow: Bool
    private var started: ContinuousClock.Instant?
    private var stopped = false
    private var job: SpeechTask?
    private(set) var heldMilliseconds = 0
    private(set) var captureCount = 0
    private let readsPrice = ProcessInfo.processInfo.arguments.contains("--uitesting-voice-read-price")
    private(set) var status = "พูดได้เลย · ปล่อยปุ่มเพื่อส่ง"

    init(slow: Bool) { self.slow = slow }

    func makeFlow(chat: ChatViewModel) -> VoiceCameraFlow {
        VoiceCameraFlow(operations: .init(
            capture: {
                await chat.suspend()
                try Task.checkCancellation()
                let size = self.readsPrice ? CGSize(width: 768, height: 512) : CGSize(width: 128, height: 128)
                let renderer = UIGraphicsImageRenderer(size: size)
                let data = renderer.jpegData(withCompressionQuality: 0.9) { context in
                    UIColor.white.setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                    if self.readsPrice {
                        let attributes: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 60, weight: .semibold),
                            .foregroundColor: UIColor.black
                        ]
                        for (index, line) in ["COFFEE MENU", "Latte", "Price: 85 THB", "Open daily"].enumerated() {
                            (line as NSString).draw(at: CGPoint(x: 38, y: 44 + index * 106), withAttributes: attributes)
                        }
                    } else {
                        UIColor.blue.setFill()
                        context.fill(CGRect(x: 32, y: 32, width: 64, height: 64))
                    }
                }
                await chat.setPhoto(data, openConversation: false)
                try Task.checkCancellation()
                guard chat.photoURL != nil, chat.error == nil else { throw VoiceCameraError.photoPreparation }
                self.captureCount += 1
            },
            startListening: {
                self.started = .now
                self.stopped = false
                self.heldMilliseconds = 0
                self.status = "พูดได้เลย · ปล่อยปุ่มเพื่อส่ง"
            },
            finishListening: {
                guard self.stopped else { throw VoiceCameraError.emptySpeech }
                self.status = "กำลังถอดเสียงบนเครื่อง…"
                let delay = self.slow ? 4.0 : 0.1
                let transcript = self.readsPrice ? "Read only the price" : "What colors are in this picture?"
                // The worker deliberately ignores cancellation. SpeechTask must
                // return the waiter and discard its later synthetic transcript.
                let job = SpeechTask {
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                            continuation.resume(returning: transcript)
                        }
                    }
                }
                self.job = job
                return try await job.value(timeout: .seconds(10))
            },
            stopListening: {
                guard !self.stopped, let started = self.started else { return }
                self.stopped = true
                self.heldMilliseconds = Int(started.duration(to: .now) / .milliseconds(1))
            },
            cancelListening: { self.job?.cancel() },
            releaseSpeech: { self.job?.cancel(); self.job = nil },
            submitQuestion: { question in
                chat.action = .question
                chat.send(question)
                await chat.waitForPendingResponse()
                try Task.checkCancellation()
                if let error = chat.error { throw VoiceCameraError.inference(error) }
            },
            inputLevel: { 0.5 },
            speechStatus: { self.status },
            cancelQuestion: { chat.stop() },
            requiresFreshPhoto: { NearbyObjectRequest.parse($0) != nil }
        ))
    }
}
#endif

/// UIControl delivers the physical touch-up/cancel even when observable camera
/// state changes during the hold. LongPressGesture.onEnded reports recognition,
/// which previously required a separate tap to actually finish recording.
private struct ShutterTouchSurface: UIViewRepresentable {
    let isEnabled: Bool
    let isObscured: Bool
    let isBusy: Bool
    let isListening: Bool
    let pressBegan: () -> Void
    let pressEnded: () -> Void
    let pressCancelled: () -> Void
    let activated: () -> Void
    let startAccessibleVoice: () -> Void
    let startAccessibleFollowUp: (() -> Void)?
    let finishAccessibleVoice: () -> Void
    @Environment(\.appLanguage) private var appLanguage

    func makeUIView(context: Context) -> ShutterTouchControl { ShutterTouchControl() }

    func updateUIView(_ control: ShutterTouchControl, context: Context) {
        control.isEnabled = isEnabled
        control.pressBegan = pressBegan
        control.pressEnded = pressEnded
        control.pressCancelled = pressCancelled
        control.activated = activated
        control.startAccessibleVoice = startAccessibleVoice
        control.startAccessibleFollowUp = startAccessibleFollowUp
        control.finishAccessibleVoice = finishAccessibleVoice
        control.isAccessibilityElement = !isObscured
        control.accessibilityElementsHidden = isObscured
        control.accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
        control.accessibilityIdentifier = "shutter"
        control.accessibilityLabel = appLanguage.text(isBusy && !isListening ? "หยุดการทำงาน" : "ถ่ายภาพ")
        control.accessibilityHint = appLanguage.text("กดค้างแล้วพูดคำถาม ปล่อยปุ่มเพื่อส่ง แตะสั้นเพื่อถ่ายภาพ")
        control.accessibilityValue = isListening ? appLanguage.text("กำลังฟัง") : nil
        if isListening {
            control.accessibilityCustomActions = [UIAccessibilityCustomAction(
                name: appLanguage.text("ส่งคำถามเสียง"), target: control, selector: #selector(ShutterTouchControl.finishVoice))]
        } else if !isBusy && isEnabled {
            var actions = [UIAccessibilityCustomAction(
                name: appLanguage.text("เริ่มถามด้วยเสียง"), target: control, selector: #selector(ShutterTouchControl.startVoice))]
            if startAccessibleFollowUp != nil {
                actions.append(UIAccessibilityCustomAction(
                    name: appLanguage.text("ถามต่อจากภาพนี้"), target: control, selector: #selector(ShutterTouchControl.startFollowUp)))
            }
            control.accessibilityCustomActions = actions
        } else { control.accessibilityCustomActions = nil }
    }
}

@MainActor private final class ShutterTouchControl: UIControl {
    var pressBegan: () -> Void = {}
    var pressEnded: () -> Void = {}
    var pressCancelled: () -> Void = {}
    var activated: () -> Void = {}
    var startAccessibleVoice: () -> Void = {}
    var startAccessibleFollowUp: (() -> Void)?
    var finishAccessibleVoice: () -> Void = {}
    private var hasActivePress = false

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled, !hasActivePress else { return false }
        hasActivePress = true
        pressBegan()
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        guard hasActivePress else { return }
        hasActivePress = false
        pressEnded()
    }

    override func cancelTracking(with event: UIEvent?) {
        guard hasActivePress else { return }
        hasActivePress = false
        pressCancelled()
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        activated()
        return true
    }

    @objc func startVoice() -> Bool { startAccessibleVoice(); return true }
    @objc func startFollowUp() -> Bool {
        guard isEnabled, let startAccessibleFollowUp else { return false }
        startAccessibleFollowUp()
        return true
    }
    @objc func finishVoice() -> Bool { finishAccessibleVoice(); return true }
}

private struct AudioLevelMark: View {
    let level: Float
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5) { index in
                Capsule().fill(LunaTheme.gold)
                    .frame(width: 3, height: 5 + CGFloat(min(1, max(0, level))) * CGFloat([13, 24, 32, 22, 11][index]))
            }
        }.frame(width: 29, height: 37).accessibilityHidden(true)
    }
}

struct ConversationSheet: View {
    @Bindable var chat: ChatViewModel
    let retake: () -> Void
    var clearPresentation: () -> Void = {}
    @FocusState private var isTyping: Bool
    @State private var showPerformance = false
    @State private var showRegionSelection = false
    @State private var showTextSources = false
    @Environment(\.appLanguage) private var appLanguage

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let photo = chat.photo {
                    Image(uiImage: photo).resizable().scaledToFill().frame(width: 42, height: 50)
                        .clipShape(.rect(cornerRadius: 9)).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("ภาพและข้อความ").font(LunaTheme.font(.headline))
                    Text(appLanguage.text(chat.status)).font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.muted)
                        .accessibilityIdentifier("modelStatus")
                }
                Spacer(minLength: 4)
                Menu {
                    Button("ข้อมูลการทำงาน", systemImage: "speedometer") { showPerformance = true }
                    Button("ล้างบริบท / เริ่มถามใหม่", systemImage: "bubble.left") {
                        chat.clearConversation()
                        clearPresentation()
                    }
                        .disabled(chat.isWorking).accessibilityIdentifier("clearContext")
                    Button("ถ่ายใหม่", systemImage: "camera") { retake() }.disabled(chat.isWorking)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }.accessibilityLabel("ตัวเลือกภาพ")
                Button("ถ่ายใหม่", action: retake).font(LunaTheme.font(.subheadline)).disabled(chat.isWorking)
                    .accessibilityIdentifier("retake")
            }.padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 15)
            Picker("งานที่ต้องการ", selection: $chat.action) {
                ForEach(PhotoAction.allCases) { action in
                    Text(appLanguage.text(action.title)).tag(action).accessibilityIdentifier("mode_\(action.rawValue)")
                }
            }.pickerStyle(.segmented).disabled(chat.isWorking)
                .padding(.horizontal, 20).padding(.bottom, 12)
                .accessibilityIdentifier("photoAction")
            Button { isTyping = false; showRegionSelection = true } label: {
                HStack(spacing: 12) {
                    if let photo = chat.photo {
                        RegionThumbnail(photo: photo, region: chat.region).frame(width: 40, height: 40)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chat.selectedSourceTitle.map { appLanguage.sourceTitle($0) }
                            ?? (chat.region == .full ? appLanguage.text("ทั้งภาพ") : appLanguage.text("กรอบที่เลือก") + " · " + appLanguage.regionLabel(chat.region)))
                            .font(LunaTheme.font(.subheadline).weight(.medium))
                        Text("แตะเพื่อเลือกพื้นที่ข้อความ").font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "crop").font(LunaTheme.font(.title3))
                }.contentShape(.rect)
            }.buttonStyle(.plain).disabled(chat.isWorking)
                .accessibilityLabel("เลือกพื้นที่").accessibilityValue(appLanguage.regionLabel(chat.region))
                .accessibilityIdentifier("chooseRegion")
                .padding(.horizontal, 20).padding(.bottom, 12)
            if chat.action == .question && chat.canRequestDistanceMeasurement {
                HStack {
                    Label("ถามระยะได้เลย · AI เลือกวัตถุอัตโนมัติ", systemImage: "ruler")
                        .font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.muted)
                    Spacer(minLength: 0)
                    Button("เลือกจุดเอง") { isTyping = false; chat.requestDistanceMeasurement() }
                        .font(LunaTheme.font(.caption)).disabled(chat.isWorking).accessibilityIdentifier("measureLiDAR")
                }.padding(.horizontal, 20).padding(.bottom, 12)
            }
            if let issue = chat.depthIssue {
                Text(appLanguage.text(issue)).font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.muted).padding(.horizontal, 20).padding(.bottom, 8)
            }
            if chat.action != .question {
                Button { isTyping = false; showTextSources = true } label: {
                    Label(appLanguage.text(chat.sourceAnalysis.map { "เลือกจากข้อความ \($0.sources.count) กลุ่ม" } ?? "แยกป้าย เมนู และฉลากในภาพ"),
                          systemImage: "rectangle.3.group")
                        .font(LunaTheme.font(.subheadline)).frame(maxWidth: .infinity, alignment: .leading)
                }.disabled(chat.isWorking).accessibilityIdentifier("discoverTextSources")
                    .padding(.horizontal, 20).padding(.bottom, 12)
            }
            Divider().overlay(.white.opacity(0.04))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if chat.messages.isEmpty { emptyConversation }
                        ForEach(chat.messages) { message in
                            messageView(message).id(message.id)
                        }
                        if let error = chat.error {
                            Label(appLanguage.text(error), systemImage: "exclamationmark.circle")
                                .font(LunaTheme.font(.subheadline)).foregroundStyle(LunaTheme.danger)
                                .padding(.vertical, 4).accessibilityIdentifier("chatError")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.messages.last?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: chat.isWorking) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            composer
        }
        .background(LunaTheme.night)
        .foregroundStyle(LunaTheme.paper)
        .font(LunaTheme.font(.body))
        .tint(LunaTheme.gold).preferredColorScheme(.dark)
        .sheet(isPresented: $showPerformance) { PerformanceSheet(chat: chat) }
        .sheet(isPresented: $showRegionSelection) {
            if let photo = chat.photo {
                RegionSelectionSheet(photo: photo, initial: chat.region) { chat.selectRegion($0) }
            }
        }
        .sheet(isPresented: $showTextSources) { TextSourcesSheet(chat: chat) }
        .sheet(isPresented: $chat.showDistanceSelection, onDismiss: { chat.cancelDistanceSelection() }) {
            if let photo = chat.photo, let depth = chat.depth {
                DistanceSelectionSheet(photo: photo, depth: depth, initialPoint: chat.selectedDistancePoint) {
                    chat.confirmDistancePoint($0)
                }
            }
        }
        .onChange(of: chat.action) { _, _ in isTyping = false }
    }

    private var emptyConversation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appLanguage.text(chat.action == .question ? "อยากรู้อะไรจากภาพนี้?"
                 : chat.action == .read ? "อ่านตามข้อความในภาพ" : "เก็บใจความสำคัญให้สั้นลง"))
                .font(LunaTheme.font(.title3).weight(.medium))
            if chat.action == .question {
                Button("ในภาพมีอะไรบ้าง?") { chat.send("ในภาพมีอะไรบ้าง?") }
                    .font(LunaTheme.font(.subheadline)).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.white.opacity(0.07), in: .capsule).disabled(chat.isWorking)
            } else {
                Text(appLanguage.text(chat.action == .read ? "อ่านทั้งภาพเพื่อแยกข้อความเป็นกลุ่ม หรือแตะแยกป้าย เมนู และฉลากเพื่อเลือกเฉพาะชิ้น"
                     : "เลือกพื้นที่แล้วกดสรุปข้อความ หรือพิมพ์เรื่องที่อยากให้เน้นด้านล่าง"))
                    .font(LunaTheme.font(.subheadline)).foregroundStyle(LunaTheme.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
    }

    private func messageView(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if message.isUser { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 8) {
                if !message.isUser {
                    Text(appLanguage.text(message.action == .read ? "ข้อความจากภาพ" : "LunaV")).font(LunaTheme.font(.caption).weight(.semibold)).foregroundStyle(LunaTheme.gold)
                }
                if message.isUser, let region = message.region {
                    HStack(spacing: 8) {
                        if let photo = chat.photo { RegionThumbnail(photo: photo, region: region).frame(width: 32, height: 32) }
                        Text(message.sourceTitle.map { appLanguage.sourceTitle($0) }
                            ?? (region == .full ? appLanguage.text("ทั้งภาพ") : appLanguage.text("กรอบที่เลือก") + " · " + appLanguage.regionLabel(region)))
                            .font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.muted)
                    }
                }
                if !message.isUser, let title = message.sourceTitle {
                    Text(appLanguage.sourceTitle(title)).font(LunaTheme.font(.subheadline).weight(.medium)).foregroundStyle(LunaTheme.muted)
                }
                if message.text.isEmpty && chat.isWorking {
                    HStack(spacing: 10) { ProgressView().controlSize(.small); Text("กำลังคิด…").foregroundStyle(LunaTheme.muted) }
                } else {
                    if message.action == .read && !message.sources.isEmpty {
                        ForEach(message.sources) { source in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    if let photo = chat.photo { RegionThumbnail(photo: photo, region: source.region).frame(width: 36, height: 36) }
                                    Text(appLanguage.sourceTitle(source)).font(LunaTheme.font(.subheadline).weight(.semibold)).foregroundStyle(LunaTheme.gold)
                                }
                                Text(verbatim: source.text).font(LunaTheme.font(.body)).textSelection(.enabled)
                                Button("สรุปกลุ่มนี้") {
                                    chat.action = .summarize; chat.selectSource(source); chat.send()
                                }.font(LunaTheme.font(.caption)).disabled(chat.isWorking)
                            }.padding(.vertical, 8)
                            Divider()
                        }
                    } else {
                        Text(verbatim: message.text).font(LunaTheme.font(.body)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let source = message.sourceText {
                    DisclosureGroup("ข้อความที่ใช้สรุป") {
                        Text(verbatim: source).font(LunaTheme.font(.subheadline)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }.font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.muted)
                }
                if !message.isUser && !message.text.isEmpty {
                    Button { UIPasteboard.general.string = message.text } label: {
                        Label("คัดลอก", systemImage: "doc.on.doc").font(LunaTheme.font(.caption))
                    }.accessibilityIdentifier("copyAnswer")
                }
                if let distance = message.distance, let photo = chat.photo {
                    DistancePointThumbnail(photo: photo, point: distance.point, region: message.distanceTarget?.region)
                        .frame(width: 120, height: 120)
                    Text(verbatim: "\(message.distanceTarget?.label ?? appLanguage.text("ตำแหน่งที่วัด")) · \(distance.capturedAt.formatted(.dateTime.hour().minute().locale(appLanguage.locale)))")
                        .font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.muted)
                        .accessibilityIdentifier("distanceProvenance")
                }
                if message.truncated {
                    Text("คำตอบถึงขีดจำกัดแล้ว ลองเลือกพื้นที่เล็กลง")
                        .font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.danger)
                }
                if message.interrupted { Text("หยุดการตอบแล้ว").font(LunaTheme.font(.caption)).foregroundStyle(LunaTheme.muted) }
            }
            .padding(message.isUser ? 14 : 0)
            .background(message.isUser ? LunaTheme.gold.opacity(0.13) : .clear, in: .rect(cornerRadius: 19))
            if !message.isUser { Spacer(minLength: 16) }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                if chat.action != .read {
                    TextField(appLanguage.text(chat.action.placeholder), text: $chat.question, axis: .vertical)
                        .lineLimit(1...5).font(LunaTheme.font(.body)).focused($isTyping)
                        .padding(.horizontal, 17).padding(.vertical, 13)
                        .background(.white.opacity(0.07), in: .rect(cornerRadius: 24))
                        .accessibilityIdentifier("questionInput")
                        .onChange(of: chat.question) { _, newValue in
                            if newValue.count > 2_000 { chat.question = String(newValue.prefix(2_000)) }
                        }
                }
                Button {
                    isTyping = false
                    if chat.isWorking { chat.stop() } else { chat.send() }
                } label: {
                    if chat.action == .question {
                        Image(systemName: chat.isWorking ? "stop.fill" : "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(LunaTheme.night).frame(width: 46, height: 46)
                            .background(LunaTheme.gold, in: .circle)
                    } else {
                        Label(appLanguage.text(chat.isWorking ? "หยุด" : chat.action.title),
                              systemImage: chat.isWorking ? "stop.fill" : chat.action == .read ? "text.viewfinder" : "text.alignleft")
                            .font(LunaTheme.font(.subheadline).weight(.semibold)).foregroundStyle(LunaTheme.night)
                            .padding(.horizontal, 18).frame(height: 46).frame(maxWidth: chat.action == .read ? .infinity : nil)
                            .background(LunaTheme.gold, in: .capsule)
                    }
                }
                .disabled(!chat.isWorking && !chat.canSend)
                .opacity(chat.isWorking || chat.canSend ? 1 : 0.35)
                .accessibilityLabel(appLanguage.text(chat.isWorking ? "หยุดการตอบ" : chat.action == .question ? "ส่งคำถาม" : chat.action.title))
                .accessibilityIdentifier("sendQuestion")
            }.padding(.horizontal, 16).padding(.top, 6)
            Text(appLanguage.text(chat.action == .question ? "ประมวลผลบนเครื่องของคุณ" : "ตรวจทานข้อความกับภาพก่อนนำไปใช้")).font(LunaTheme.font(.caption2)).foregroundStyle(LunaTheme.faint)
        }.padding(.bottom, 10)
    }
}

struct PerformanceSheet: View {
    let chat: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    var body: some View {
        NavigationStack {
            List {
                Section("เครื่องนี้") {
                    LabeledContent("อุปกรณ์", value: UIDevice.current.model)
                    LabeledContent("ระบบ", value: "iOS \(UIDevice.current.systemVersion)")
                    LabeledContent("RAM", value: ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory))
                    LabeledContent("โปรไฟล์อัตโนมัติ", value: appLanguage.text(chat.policy.name))
                    LabeledContent("จำนวนโทเคนภาพสูงสุด", value: "\(chat.policy.maxPixels / 1_024)")
                    LabeledContent("ความร้อน", value: appLanguage.text(thermalDescription))
                }.listRowBackground(LunaTheme.deep)
                Section("ระยะของภาพนี้") {
                    if let depth = chat.depth {
                        LabeledContent("แหล่งข้อมูล", value: appLanguage.text("\(depth.depthSource.title) จากภาพถ่ายเดียวกัน"))
                        LabeledContent("แผนที่ระยะ", value: "\(depth.width) × \(depth.height)")
                        LabeledContent("รูปแบบระยะ", value: appLanguage.text(depth.depthSource.isEstimated ? "ประมาณจากภาพและข้อมูลเลนส์"
                                       : depth.isFiltered ? "ประมวลผลช่องว่างโดยระบบ" : "ข้อมูลเซ็นเซอร์ดิบ"))
                        LabeledContent("เวลาถ่าย", value: depth.capturedAt.formatted(.dateTime.locale(appLanguage.locale)))
                        Text("AI หาวัตถุจากคำถามแล้วอ่านแผนที่ระยะของพื้นที่นั้น ค่าระยะเป็นของตอนถ่ายภาพ")
                            .font(LunaTheme.font(.footnote)).foregroundStyle(LunaTheme.muted)
                        if depth.isFiltered {
                            Text("เป็นค่าประมาณจาก depth ที่ระบบกรองและเติมช่องว่าง ไม่ใช่ค่าดิบทุกพิกเซล")
                                .font(LunaTheme.font(.footnote)).foregroundStyle(LunaTheme.muted)
                        }
                        if depth.depthSource.isEstimated {
                            Text("Depth Anything 3 ประเมินระยะจากภาพ ค่าจริงอาจคลาดเคลื่อน โดยเฉพาะกระจก พื้นผิวสะท้อน และฉากที่โมเดลไม่คุ้นเคย")
                                .font(LunaTheme.font(.footnote)).foregroundStyle(LunaTheme.muted)
                        }
                    } else { Text(appLanguage.text(chat.depthIssue ?? "ภาพนี้ไม่มีข้อมูลระยะ ใช้การตอบจากภาพตามปกติ")) }
                }.listRowBackground(LunaTheme.deep)
                Section("โมเดล") {
                    LabeledContent("ชื่อ", value: "Qwen3-VL-2B-Instruct")
                    LabeledContent("น้ำหนักภาษา", value: "4-bit · group 64")
                    LabeledContent("ประมวลผล", value: "MLX · Metal GPU")
                    Text("ความละเอียดปรับตามเครื่อง ถามภาพตอบสั้น ส่วนอ่านข้อความใช้ OCR บนเครื่องและสรุปด้วยโมเดล")
                        .font(LunaTheme.font(.footnote)).foregroundStyle(LunaTheme.muted)
                }.listRowBackground(LunaTheme.deep)
                if let result = chat.metrics {
                    Section("การตอบล่าสุด") {
                        LabeledContent(appLanguage.text(result.stoppedForRepetition ? "ความเร็วโดยประมาณ" : "ความเร็ว"), value: String(format: "%.1f tokens/s", result.tokensPerSecond))
                        LabeledContent("สร้างโทเคนแรกหลัง", value: appLanguage.text(String(format: "%.2f วินาที", result.firstTokenSeconds)))
                        LabeledContent("เวลารวม", value: appLanguage.text(String(format: "%.2f วินาที", result.totalSeconds)))
                        LabeledContent(appLanguage.text(result.stoppedForRepetition ? "โทเคนก่อนหยุด (ประมาณ)" : "โทเคนคำตอบ"), value: "\(result.generatedTokens)")
                        LabeledContent("หน่วยความจำ MLX สูงสุด", value: ByteCountFormatter.string(fromByteCount: Int64(result.peakMemoryBytes), countStyle: .memory))
                        LabeledContent("บริบทที่ใช้", value: "\(result.contextTokens) tokens")
                        LabeledContent("ปรับบริบทอัตโนมัติ", value: appLanguage.text(result.contextReset ? "ใช่" : "ไม่"))
                        LabeledContent("สร้างคำตอบใหม่", value: appLanguage.text("\(result.retryCount) ครั้ง"))
                    }.listRowBackground(LunaTheme.deep)
                }
                #if targetEnvironment(simulator)
                Section { Text("Simulator ใช้ตรวจ UI เท่านั้น ต้องรันบน iPhone เพื่อทดสอบความเร็วโมเดลจริง").font(LunaTheme.font(.footnote)) }
                    .listRowBackground(LunaTheme.deep)
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(LunaTheme.night)
            .navigationTitle("ข้อมูลการทำงาน").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LunaTheme.night, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("เสร็จ") { dismiss() } } }
        }
        .font(LunaTheme.font(.body))
        .foregroundStyle(LunaTheme.paper)
        .tint(LunaTheme.gold)
        .preferredColorScheme(.dark)
    }
    private var thermalDescription: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "ปกติ"
        case .fair: "อุ่น"
        case .serious: "ร้อน · ลดการใช้ทรัพยากร"
        case .critical: "ร้อนมาก · พักการทำงาน"
        @unknown default: "ไม่ทราบ"
        }
    }
}
