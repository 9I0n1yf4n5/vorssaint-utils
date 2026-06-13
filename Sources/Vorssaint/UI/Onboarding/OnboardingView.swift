import ServiceManagement
import SwiftUI

/// First-run experience, also reachable later through Settings › About.
/// Seven steps: welcome & language, Accessibility, Screen Recording, system
/// monitor, optional features, status verification and the final summary.
/// Whether onboarding is the first-run tour or the shorter "what's new" pass
/// shown once to people updating to this version.
enum OnboardingMode {
    case full
    case whatsNew

    var steps: [OnboardingStep] {
        switch self {
        case .full:
            return [.welcome, .accessibility, .screenRecording, .monitor, .optionalFeatures,
                    .cutPaste, .autoQuit, .uninstaller, .shelf, .status, .done]
        case .whatsNew:
            return [.whatsNew, .cutPaste, .autoQuit, .uninstaller, .shelf, .done]
        }
    }
}

enum OnboardingStep {
    case welcome, accessibility, screenRecording, monitor, optionalFeatures
    case whatsNew, cutPaste, autoQuit, uninstaller, shelf
    case status, done
}

struct OnboardingView: View {
    var mode: OnboardingMode = .full
    var onFinish: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    /// Persisted so the flow resumes where it stopped — macOS relaunches the
    /// app when Screen Recording is granted mid-onboarding.
    @AppStorage(DefaultsKey.onboardingStep) private var index = 0

    private var steps: [OnboardingStep] { mode.steps }
    private var current: OnboardingStep { steps[min(max(0, index), steps.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            navigationBar
        }
        .frame(width: 540, height: 600)
        .onAppear {
            if !steps.indices.contains(index) { index = 0 }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch current {
        case .welcome: WelcomeStep()
        case .accessibility: PermissionStep(kind: .accessibility,
                                            icon: "accessibility",
                                            title: l10n.s.obStepAccessibilityTitle,
                                            body: l10n.s.obStepAccessibilityBody,
                                            why: l10n.s.obAccessibilityWhy)
        case .screenRecording: PermissionStep(kind: .screenRecording,
                                              icon: "rectangle.dashed.badge.record",
                                              title: l10n.s.obStepRecordingTitle,
                                              body: l10n.s.obStepRecordingBody,
                                              why: l10n.s.obRecordingWhy)
        case .monitor: MonitorStep()
        case .optionalFeatures: OptionalFeaturesStep()
        case .whatsNew: WhatsNewIntroStep()
        case .cutPaste: CutPasteShowcaseStep()
        case .autoQuit: AutoQuitShowcaseStep()
        case .uninstaller: UninstallerShowcaseStep()
        case .shelf: ShelfShowcaseStep()
        case .status: StatusStep()
        case .done: DoneStep()
        }
    }

    private var navigationBar: some View {
        HStack {
            Button(l10n.s.obBack) {
                withAnimation(.easeInOut(duration: 0.2)) { index = max(0, index - 1) }
            }
            .disabled(index == 0)

            Spacer()

            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: i == index ? 18 : 7, height: 7)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
                }
            }

            Spacer()

            Button(primaryButtonTitle) {
                if index >= steps.count - 1 {
                    index = 0
                    onFinish()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { index += 1 }
                }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    private var primaryButtonTitle: String {
        if index >= steps.count - 1 { return l10n.s.obStart }
        switch current {
        case .accessibility where !permissions.accessibility,
             .screenRecording where !permissions.screenRecording:
            return l10n.s.obSkipStep
        default:
            return l10n.s.obContinue
        }
    }
}

// MARK: - Step 1: welcome & language

private struct WelcomeStep: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.spaceGradient
                VStack(spacing: 10) {
                    BrandMark(width: 130)
                    Text(AppInfo.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text(l10n.s.obStepWelcomeBody)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.top, 12)
            }
            .frame(height: 220)

            VStack(alignment: .leading, spacing: 16) {
                Picker(l10n.s.obLanguageLabel, selection: $l10n.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)

                featureRow(icon: "bolt.fill",
                           title: l10n.s.obWelcomeBullet1Title,
                           text: l10n.s.obWelcomeBullet1Body)
                featureRow(icon: "gauge.with.dots.needle.50percent",
                           title: l10n.s.obWelcomeBullet2Title,
                           text: l10n.s.obWelcomeBullet2Body)
                featureRow(icon: "rectangle.on.rectangle",
                           title: l10n.s.obWelcomeBullet3Title,
                           text: l10n.s.obWelcomeBullet3Body)
            }
            .padding(24)
        }
    }

    private func featureRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.spaceGradient)
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Steps 2–3: permissions

private struct PermissionStep: View {
    @ObservedObject private var l10n = L10n.shared
    let kind: PermissionKind
    let icon: String
    let title: String
    let body_: String
    let why: String

    init(kind: PermissionKind, icon: String, title: String, body: String, why: String) {
        self.kind = kind
        self.icon = icon
        self.title = title
        self.body_ = body
        self.why = why
    }

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(icon: icon, title: title, subtitle: body_)

            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(kind: kind)
                Text(l10n.s.permissionRestartNote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .padding(.horizontal, 28)

            Text(why)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)

            Spacer()
        }
    }
}

// MARK: - Step 4: system monitor

private struct MonitorStep: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(icon: "gauge.with.dots.needle.50percent",
                       title: l10n.s.obStepMonitorTitle,
                       subtitle: l10n.s.obStepMonitorBody)

            // A live taste of the panel's System section.
            SystemSection()
                .frame(width: 320)
                .onAppear { SystemMonitor.shared.start() }
                .onDisappear { SystemMonitor.shared.stop() }

            Text(l10n.s.obMonitorNoPermission)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Spacer()
        }
    }
}

// MARK: - Step 5: optional features

private struct OptionalFeaturesStep: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(DefaultsKey.scrollInverterEnabled) private var inverterEnabled = false
    @AppStorage(DefaultsKey.switcherEnabled) private var switcherEnabled = true
    @State private var passwordless = false
    @State private var passwordlessBusy = false
    @State private var passwordlessError = false

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(icon: "slider.horizontal.3",
                       title: l10n.s.obStepOptionalTitle,
                       subtitle: l10n.s.obStepOptionalBody)

            VStack(alignment: .leading, spacing: 14) {
                Toggle(l10n.s.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Toggle(l10n.s.invertMouseScroll, isOn: $inverterEnabled)
                        .onChange(of: inverterEnabled) { _, _ in
                            ScrollInverter.shared.syncWithPreferences()
                        }
                    Text(l10n.s.scrollTrackpadNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Toggle(l10n.s.switcherEnable, isOn: $switcherEnabled)
                        .onChange(of: switcherEnabled) { _, _ in
                            AppSwitcher.shared.syncWithPreferences()
                        }
                    Text(l10n.s.switcherEnableCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Toggle(passwordlessBusy ? l10n.s.configuring : l10n.s.obPasswordlessToggle,
                           isOn: passwordlessBinding)
                        .disabled(passwordlessBusy)
                    Text(l10n.s.obPasswordlessCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if passwordlessError {
                        Text(l10n.s.sudoersFailed)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .padding(.horizontal, 28)

            Spacer()
        }
        .onAppear {
            DispatchQueue.global(qos: .utility).async {
                let configured = Sudoers.isConfigured()
                DispatchQueue.main.async { passwordless = configured }
            }
        }
    }

    private var passwordlessBinding: Binding<Bool> {
        Binding(
            get: { passwordless },
            set: { enable in
                passwordlessBusy = true
                passwordlessError = false
                let finish: (Bool) -> Void = { ok in
                    DispatchQueue.global(qos: .utility).async {
                        let configured = Sudoers.isConfigured()
                        DispatchQueue.main.async {
                            passwordlessBusy = false
                            passwordlessError = !ok
                            passwordless = configured
                            KeepAwakeManager.shared.refreshPasswordlessStatus()
                        }
                    }
                }
                if enable {
                    Sudoers.install(completion: finish)
                } else {
                    Sudoers.remove(completion: finish)
                }
            }
        )
    }
}

// MARK: - Step 6: status verification

private struct StatusStep: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.scrollInverterEnabled) private var inverterEnabled = false
    @AppStorage(DefaultsKey.switcherEnabled) private var switcherEnabled = true

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(icon: "checklist",
                       title: l10n.s.obStepStatusTitle,
                       subtitle: l10n.s.obStepStatusBody)

            VStack(spacing: 0) {
                statusRow(name: l10n.s.permissionAccessibility,
                          needed: inverterEnabled || switcherEnabled,
                          granted: permissions.accessibility)
                Divider().padding(.vertical, 8)
                statusRow(name: l10n.s.permissionScreenRecording,
                          needed: switcherEnabled,
                          granted: permissions.screenRecording)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .padding(.horizontal, 28)

            Button(l10n.s.obStatusRecheck) {
                permissions.refresh()
            }
            .controlSize(.small)

            Text(l10n.s.permissionRestartNote)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
    }

    private func statusRow(name: String, needed: Bool, granted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill"
                                      : (needed ? "exclamationmark.circle.fill" : "minus.circle"))
                .foregroundStyle(granted ? .green : (needed ? .orange : .secondary))
            Text(name)
            Spacer()
            Text(granted ? l10n.s.permissionGranted : l10n.s.permissionMissing)
                .font(.caption)
                .foregroundStyle(granted ? .green : (needed ? .orange : .secondary))
        }
    }
}

// MARK: - Step 7: done

private struct DoneStep: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.spaceGradient
                VStack(spacing: 14) {
                    BrandMark(width: 150)
                    Text(l10n.s.obStepDoneTitle)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text(l10n.s.obStepDoneBody)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(height: 300)

            VStack(spacing: 10) {
                Image(systemName: "menubar.arrow.up.rectangle")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                Text(l10n.s.obDoneHint)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
            }
            .padding(.top, 36)

            Spacer()
        }
    }
}

// MARK: - Shared header

private struct StepHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.spaceGradient)
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.system(size: 19, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 48)
        }
        .padding(.top, 30)
    }
}
