import SwiftUI

struct AutoQuitSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = AutoQuitService.shared
    @AppStorage(DefaultsKey.autoQuitEnabled) private var enabled = false

    var body: some View {
        Form {
            Section {
                Toggle(l10n.s.autoQuitEnable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        AutoQuitService.shared.syncWithPreferences()
                    }
                Text(l10n.s.autoQuitEnableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if enabled, service.isRunning {
                    Label(l10n.s.autoQuitActiveNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section(l10n.s.autoQuitHowTitle) {
                bullet("rectangle.badge.xmark", l10n.s.autoQuitStep1)
                bullet("bolt.fill", l10n.s.autoQuitStep2)
                Text(l10n.s.autoQuitPredictableNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(l10n.s.autoQuitExceptionsTitle) {
                if sortedExceptions.isEmpty {
                    Text(l10n.s.autoQuitExceptionsEmpty)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedExceptions, id: \.self) { bundleID in
                        HStack(spacing: 9) {
                            Image(nsImage: InstalledApps.icon(for: bundleID))
                                .resizable().frame(width: 20, height: 20)
                            Text(InstalledApps.name(for: bundleID))
                            Spacer()
                            Button {
                                service.removeException(bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Menu {
                    ForEach(addableApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                            if let id = app.bundleIdentifier { service.addException(id) }
                        }
                    }
                } label: {
                    Label(l10n.s.autoQuitAddApp, systemImage: "plus")
                }
                .disabled(addableApps.isEmpty)

                Text(l10n.s.autoQuitExceptionsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if enabled, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var sortedExceptions: [String] {
        service.exceptions.sorted { InstalledApps.name(for: $0).localizedCaseInsensitiveCompare(InstalledApps.name(for: $1)) == .orderedAscending }
    }

    private var addableApps: [NSRunningApplication] {
        InstalledApps.runningRegularApps()
            .filter { !service.exceptions.contains($0.bundleIdentifier ?? "") }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.tint)
                .frame(width: 18)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
