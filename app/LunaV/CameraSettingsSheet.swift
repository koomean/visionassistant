import PhotosUI
import SwiftUI

/// Everyday voice preferences come first. Manual tools remain in Settings so
/// the camera keeps its capture-and-settings interface.
struct CameraSettingsSheet: View {
    let camera: CameraController
    @Bindable var chat: ChatViewModel
    let voice: VoiceCameraFlow
    let preparation: ModelPreparation
    @State private var knownDistance = "1.0"
    @State private var showSpeechDetails = false
    @State private var showCalibration = false
    @State private var showVoiceHelp = false
    @Binding var selectedPhoto: PhotosPickerItem?
    let openManual: (PhotoAction) -> Void
    let openPerformance: () -> Void
    let useSample: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var appLanguage
    @AppStorage(CameraQuestionPreference.reusePhotoKey) private var reusePhotoOnHold = false
    @AppStorage(AppLanguage.storageKey) private var uiLanguage = AppLanguage.thai.rawValue

    private var canChangePhoto: Bool {
        preparation.isReady && !voice.isBusy && !chat.isWorking && !chat.isPreparingPhoto && !camera.isCapturing
    }

    private var canTestPhoto: Bool { chat.photo != nil && canChangePhoto }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    introduction
                    interfaceLanguage
                    speechInput
                    if let player = chat.answerSpeech { speechOutput(player) }
                    ObstacleSettingsSection(monitor: camera.obstacles)
                    testTools
                    if preparation.needsMonocularDepth || chat.depth?.depthSource == .depthAnything3Metric {
                        depthCalibration
                    }
                    systemSettings
                    privacyNote
                    aboutSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .foldAwareReadable()
            .background(LunaTheme.night)
            .scrollIndicators(.hidden)
            .navigationTitle("ตั้งค่า")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LunaTheme.night, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("เสร็จ") { dismiss() }
                        .font(LunaTheme.font(.body, weight: .semibold))
                        .accessibilityIdentifier("closeSettings")
                }
            }
        }
        .settingsToolbar()
        .font(LunaTheme.font(.body))
        .foregroundStyle(LunaTheme.paper)
        .tint(LunaTheme.gold)
        .preferredColorScheme(.dark)
        .task { chat.answerSpeech?.refreshVoices() }
    }

    private var introduction: some View {
        HStack(alignment: .center, spacing: 16) {
            Image("BrandMark")
                .resizable().scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("LunaV\(Text(".").foregroundColor(LunaTheme.gold))")
                    .font(LunaTheme.brandFont(size: 30, weight: .semibold))
                    .accessibilityLabel("LunaV")
                Text("ปรับให้พร้อมในแบบของคุณ")
                    .font(LunaTheme.font(.subheadline))
                    .foregroundStyle(LunaTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private var interfaceLanguage: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("ภาษาแอพ", subtitle: nil)
            panel {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("ภาษาแอพ", selection: $uiLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(verbatim: language.name).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("appLanguage")
                    Text("เปลี่ยนเฉพาะภาษาหน้าจอ ไม่เปลี่ยนภาษารับเสียงหรือคำตอบ")
                        .font(LunaTheme.font(.footnote))
                        .foregroundStyle(LunaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
        }
    }

    private var speechInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("ภาษาและคำถาม", subtitle: "เลือกภาษาที่คุณใช้พูดกับ LunaV")
            panel {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("ภาษาเสียง", selection: Binding(
                        get: { preparation.speech.language },
                        set: { value in
                            preparation.speech.language = value
                            Task { try? await preparation.speech.prepareForStartup() }
                        })) {
                        ForEach(NativeSpeechLanguage.allCases, id: \.self) { language in
                            Text(appLanguage.text(language.label)).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: 44)
                    .disabled(voice.isBusy || preparation.speech.hasPendingWork)
                    .accessibilityIdentifier("speechLanguage")

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: preparation.speech.isPrepared ? "checkmark.circle.fill" : "waveform")
                            .foregroundStyle(preparation.speech.isPrepared ? LunaTheme.gold : LunaTheme.blue)
                            .accessibilityHidden(true)
                        Text(appLanguage.text(preparation.speech.status))
                            .font(LunaTheme.font(.footnote))
                            .foregroundStyle(LunaTheme.muted)
                    }
                    if let error = preparation.speech.preparationError { errorNote(error) }

                    Toggle("ใช้ภาพเดิมเมื่อกดค้าง", isOn: $reusePhotoOnHold)
                        .accessibilityIdentifier("reusePhotoOnHold")
                    Text("กดค้างเพื่อถามต่อจากภาพล่าสุด แตะสั้นเพื่อถ่ายใหม่ คำสั่งช่วยหาของจะถ่ายภาพใหม่")
                        .font(LunaTheme.font(.footnote))
                        .foregroundStyle(LunaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("กดปุ่มกลางค้างแล้วพูด ปล่อยเพื่อส่งคำถาม\nแตะสั้นเพื่อถ่ายภาพอย่างเดียว")
                        .font(LunaTheme.font(.subheadline))
                        .foregroundStyle(LunaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("voiceInfo")
                    separator
                    Button {
                        Task { try? await preparation.speech.prepareForStartup() }
                    } label: {
                        actionLabel(preparation.speech.hasPendingWork ? "กำลังเตรียมภาษาเสียง…" : "เตรียม / ลองระบบเสียงอีกครั้ง",
                                    symbol: "arrow.clockwise", chevron: false)
                    }
                    .buttonStyle(.plain)
                    .disabled(voice.isBusy || preparation.speech.hasPendingWork)
                    .accessibilityIdentifier("prepareNativeSpeech")
                    if voice.isBusy {
                        Button {
                            Task { await voice.cancel() }
                        } label: { actionLabel("หยุดคำถามเสียง", symbol: "stop.circle", chevron: false) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("cancelVoice")
                    }
                    DisclosureGroup("เกี่ยวกับการรับเสียง", isExpanded: $showSpeechDetails) {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("โมเดลเสียง", value: appLanguage.text(LocalSpeechRecognizer.modelName))
                            LabeledContent("ภาษาเสียงบนเครื่อง", value: appLanguage.text(preparation.speech.isPrepared ? "พร้อมใช้งาน" : "ยังไม่พร้อม"))
                            Text("หากยังไม่มีภาษาเสียง iOS จะดาวน์โหลดจาก Apple ครั้งแรก หลังจากนั้นถอดคำถามบนเครื่อง เลือกภาษาให้ตรงกับคำถาม")
                            Text(appLanguage.text(LocalSpeechRecognizer.modelDescription))
                            Text("แอพฟังต่อแม้คุณเว้นช่วงพูด และส่งคำถามเมื่อปล่อยปุ่มเท่านั้น")
                            Text("ลองพูดว่า อ่านเฉพาะราคา หรือ ช่วยหาขวดน้ำบนโต๊ะ")
                        }
                        .font(LunaTheme.font(.footnote))
                        .foregroundStyle(LunaTheme.muted)
                        .padding(.top, 10)
                    }
                    .font(LunaTheme.font(.subheadline))
                }
                .padding(18)
            }
        }
    }

    private func speechOutput(_ player: AnswerSpeechPlayer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("เสียงอ่านคำตอบ", subtitle: "ฟังคำตอบด้วยเสียง Apple ที่อยู่ในเครื่อง")
            panel {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("อ่านคำตอบอัตโนมัติ", isOn: Binding(
                        get: { player.enabled }, set: { player.enabled = $0 }))
                        .accessibilityIdentifier("answerSpeechEnabled")
                    separator
                    voicePicker("เสียงภาษาไทย", language: "th", selection: Binding(
                        get: { player.selectedThaiVoiceID }, set: { player.selectedThaiVoiceID = $0 }), player: player)
                    voicePicker("เสียงภาษาอังกฤษ", language: "en", selection: Binding(
                        get: { player.selectedEnglishVoiceID }, set: { player.selectedEnglishVoiceID = $0 }), player: player)
                    HStack(spacing: 12) {
                        Button {
                            player.speak(preparation.speech.language == .thai
                                ? "ขวดน้ำอยู่ห่างจากกล้องประมาณหนึ่งเมตร"
                                : "The water bottle is about one meter away from the camera.", id: UUID())
                        } label: {
                            Label("ลองฟังเสียง", systemImage: "play.fill")
                                .font(LunaTheme.font(.subheadline, weight: .semibold))
                                .frame(minHeight: 32)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!player.enabled || voice.isBusy || chat.isWorking)
                        .accessibilityIdentifier("previewAnswerSpeech")
                        if player.isSpeaking {
                            Button("หยุดอ่าน", systemImage: "stop.fill") { player.stop() }
                                .font(LunaTheme.font(.subheadline))
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("stopAnswerSpeech")
                        }
                    }
                    Text(appLanguage.text(player.status))
                        .font(LunaTheme.font(.footnote))
                        .foregroundStyle(LunaTheme.muted)
                    if let error = player.error { errorNote(error) }
                    DisclosureGroup("วิธีเพิ่มเสียง", isExpanded: $showVoiceHelp) {
                        Text("เลือกเสียงที่ติดตั้งบนเครื่องได้ทันที เพิ่มเสียงคุณภาพสูงได้ใน Settings → Accessibility → Read & Speak → Voices ส่วนเสียง Siri ไม่เปิดให้แอพเลือกโดยตรง")
                            .font(LunaTheme.font(.footnote))
                            .foregroundStyle(LunaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                    .font(LunaTheme.font(.subheadline))
                }
                .padding(18)
            }
        }
    }

    private var testTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("เครื่องมือทดสอบ", subtitle: chat.photo == nil
                ? "ถ่ายภาพหรือเลือกรูปก่อนเริ่มใช้เครื่องมือ"
                : "ใช้ภาพล่าสุด เลือกพื้นที่หรือพิมพ์ถามได้เอง")
            panel {
                VStack(spacing: 0) {
                    #if targetEnvironment(simulator)
                    Button(action: useSample) {
                        actionLabel("ใช้ภาพทดสอบ", symbol: "photo.badge.checkmark")
                    }
                    .buttonStyle(.plain)
                    .disabled(!canChangePhoto)
                    .accessibilityIdentifier("samplePhoto")
                    rowSeparator
                    #endif
                    PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                        actionLabel("เลือกรูปจากคลังภาพ", symbol: "photo.on.rectangle")
                    }
                    .buttonStyle(.plain)
                    .disabled(!canChangePhoto)
                    .accessibilityIdentifier("importPhoto")
                    rowSeparator
                    manualButton("ถามเกี่ยวกับภาพ", symbol: "bubble.left.and.text.bubble.right", action: .question, id: "manualConversation")
                    rowSeparator
                    manualButton("อ่านข้อความและเลือกพื้นที่", symbol: "text.viewfinder", action: .read, id: "manualRead")
                    rowSeparator
                    manualButton("สรุปป้าย เมนู และฉลาก", symbol: "text.alignleft", action: .summarize, id: "manualSummary")
                    rowSeparator
                    Button { openManual(.question) } label: {
                        actionLabel("ทดสอบระยะและเลือกจุดเอง", symbol: "ruler")
                    }
                    .buttonStyle(.plain)
                    .disabled(!canTestPhoto || !chat.canRequestDistanceMeasurement)
                    .accessibilityIdentifier("manualLiDAR")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 3)
            }
        }
    }

    private var depthCalibration: some View {
        panel {
            DisclosureGroup(isExpanded: $showCalibration) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("ระยะจากภาพเป็นค่าประมาณ การเทียบช่วยปรับสเกลของกล้องนี้ แต่ความแม่นยำยังขึ้นกับฉาก เลนส์ และแสง")
                        .font(LunaTheme.font(.footnote))
                        .foregroundStyle(LunaTheme.muted)
                    if let depth = chat.depth, depth.depthSource == .depthAnything3Metric {
                        LabeledContent("ตัวคูณสำหรับกล้องนี้", value: String(format: "%.3f", depth.calibrationScale))
                        LabeledContent("ข้อมูลเลนส์", value: appLanguage.text(depth.focalProvenance == .exif35mm ? "ประมาณจาก EXIF" : "ค่าคาลิเบรตกล้อง"))
                        Text("ให้ผิวทึบเรียบอยู่กลางภาพ วัดจากกล้องถึงผิวด้วยตลับเมตร แล้วกรอกระยะเป็นเมตร")
                            .font(LunaTheme.font(.footnote))
                            .foregroundStyle(LunaTheme.muted)
                        TextField("ระยะจริง (เมตร)", text: $knownDistance)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("knownDepthDistance")
                        Button("เทียบระยะตรงกลางภาพ") {
                            if let meters = Double(knownDistance.replacingOccurrences(of: ",", with: ".")) {
                                chat.calibrateDepth(knownMeters: meters)
                            } else { chat.error = "กรุณากรอกระยะเป็นเมตร เช่น 1.0" }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canTestPhoto || chat.depthCameraIdentifier == nil)
                        .accessibilityIdentifier("calibrateMonocularDepth")
                        Button("คืนค่าสเกลเดิม") { chat.resetDepthCalibration() }
                            .buttonStyle(.bordered)
                            .disabled(!canTestPhoto || chat.depthCameraIdentifier == nil)
                        Text("หากปรับสเกลแล้วจุดนั้นไม่มีค่า ให้ถ่ายใหม่เพื่อคำนวณแผนที่ระยะอีกครั้ง")
                            .font(LunaTheme.font(.caption))
                            .foregroundStyle(LunaTheme.faint)
                        if let error = chat.error { errorNote(error) }
                    } else {
                        Text("ถ่ายภาพแล้วถามระยะ หรือใช้เครื่องมือเลือกจุดเองก่อน จึงจะเทียบระยะได้ ไม่จำเป็นต้องเทียบก่อนใช้งานตามปกติ")
                            .font(LunaTheme.font(.footnote))
                            .foregroundStyle(LunaTheme.muted)
                    }
                }
                .padding(.top, 14)
            } label: {
                Label("เทียบระยะ Depth Anything 3", systemImage: "ruler")
                    .font(LunaTheme.font(.subheadline, weight: .medium))
                    .frame(minHeight: 30)
            }
            .padding(18)
        }
    }

    private var systemSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("ระบบและความพร้อม", subtitle: nil)
            panel {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: preparation.isReady ? "checkmark.circle.fill" : "circle.dotted")
                            .foregroundStyle(LunaTheme.gold)
                            .accessibilityHidden(true)
                        Text(appLanguage.text(preparation.status))
                            .font(LunaTheme.font(.subheadline))
                            .foregroundStyle(LunaTheme.muted)
                    }
                    LabeledContent("ระยะจากกล้องหลัง", value: preparation.needsMonocularDepth ? "Depth Anything 3 Metric" : "LiDAR")
                        .font(LunaTheme.font(.footnote))
                        .foregroundStyle(LunaTheme.muted)
                    Text("แอพจัดการหน่วยความจำให้อัตโนมัติ เครื่องที่มี RAM จำกัดจะโหลดโมเดลเมื่อใช้และคืนหลังตอบ จึงอาจมีช่วงรอระหว่างคำถาม")
                        .font(LunaTheme.font(.footnote))
                        .foregroundStyle(LunaTheme.faint)
                    separator
                    Button {
                        chat.clearConversation()
                        voice.resetPresentation()
                    } label: { actionLabel("ล้างบริบท / เริ่มถามใหม่", symbol: "bubble.left", chevron: false) }
                        .buttonStyle(.plain)
                        .disabled(!canChangePhoto)
                        .accessibilityIdentifier("settingsClearContext")
                    separator
                    Button(action: openPerformance) {
                        actionLabel("ข้อมูลโมเดล เครื่อง และ LiDAR", symbol: "speedometer")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("cameraPerformance")
                    separator
                    Button { openSystemSettings() } label: {
                        actionLabel(camera.permissionDenied ? "เปิดสิทธิ์กล้องและไมโครโฟน" : "สิทธิ์ไมโครโฟนและกล้อง", symbol: "lock.open")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("systemPermissions")
                }
                .padding(18)
            }
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(LunaTheme.gold)
                .accessibilityHidden(true)
            Text("ภาพ เสียง ข้อความ และคำตอบประมวลผลบนเครื่องของคุณ")
                .font(LunaTheme.font(.footnote))
                .foregroundStyle(LunaTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("เกี่ยวกับ", subtitle: nil)
            panel {
                NavigationLink {
                    AboutScreen()
                } label: {
                    actionLabel("เกี่ยวกับ LunaV", symbol: "info.circle")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
                .accessibilityIdentifier("openAbout")
            }
        }
    }

    private func sectionHeading(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title))
                .font(LunaTheme.font(.title3, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(LocalizedStringKey(subtitle))
                    .font(LunaTheme.font(.footnote))
                    .foregroundStyle(LunaTheme.muted)
            }
        }
        .padding(.horizontal, 2)
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LunaTheme.deep, in: .rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(LunaTheme.line, lineWidth: 1) }
    }

    nonisolated private func actionLabel(_ title: String, symbol: String, chevron: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(LunaTheme.blue)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(title))
                .font(LunaTheme.font(.subheadline, weight: .medium))
                .foregroundStyle(LunaTheme.paper)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LunaTheme.faint)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 48, alignment: .leading)
        .contentShape(.rect)
    }

    private var separator: some View { Rectangle().fill(LunaTheme.line).frame(height: 1) }
    private var rowSeparator: some View { separator.padding(.leading, 36) }

    private func voicePicker(_ title: String, language: String, selection: Binding<String?>,
                             player: AnswerSpeechPlayer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(LunaTheme.font(.caption))
                .foregroundStyle(LunaTheme.muted)
            Picker(LocalizedStringKey(title), selection: selection) {
                Text("อัตโนมัติ").tag(String?.none)
                ForEach(player.availableVoices.filter { $0.language.hasPrefix(language + "-") }) { voice in
                    Text(appLanguage.text(voice.label)).tag(Optional(voice.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .font(LunaTheme.font(.subheadline))
            .disabled(voice.isBusy || chat.isWorking)
            .accessibilityIdentifier("answerVoice_\(language)")
        }
    }

    private func manualButton(_ title: String, symbol: String, action: PhotoAction, id: String) -> some View {
        Button { openManual(action) } label: { actionLabel(title, symbol: symbol) }
            .buttonStyle(.plain)
            .disabled(!canTestPhoto)
            .accessibilityIdentifier(id)
    }

    private func errorNote(_ message: String) -> some View {
        Text(appLanguage.text(message))
            .font(LunaTheme.font(.footnote))
            .foregroundStyle(LunaTheme.danger)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

private extension View {
    @ViewBuilder func settingsToolbar() -> some View {
        if #available(iOS 27.1, *) {
            // This sheet has one dismissal action. Keep it above the scrolling
            // content instead of letting the shared side bar collapse it.
            toolbarVerticalBehavior(.disabled)
        } else { self }
    }
}
