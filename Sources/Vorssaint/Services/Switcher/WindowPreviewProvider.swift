import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Captures window thumbnails for the switcher with ScreenCaptureKit.
///
/// Thumbnails live only in this in-memory cache: stale images make cards
/// appear instantly on the next invocation while fresh captures stream in.
/// Without Screen Recording permission the provider stays silent and the
/// switcher falls back to app icons.
final class WindowPreviewProvider {
    static let shared = WindowPreviewProvider()

    /// Longest thumbnail edge, in pixels (2x for Retina sharpness).
    private static let maxPixelSize: CGFloat = 640

    private var cache: [CGWindowID: CGImage] = [:]
    private var captureTask: Task<Void, Never>?

    private init() {}

    func cachedPreview(for windowID: CGWindowID) -> CGImage? {
        cache[windowID]
    }

    /// Refreshes thumbnails for the previewable `items`, invoking `onUpdate`
    /// on the main thread as each capture lands. Earlier entries are captured
    /// first, so pass items in display order. Tab entries share their host
    /// window's capture, so each backing window is captured once.
    func refreshPreviews(for items: [SwitcherItem],
                         onUpdate: @escaping (CGWindowID, CGImage) -> Void) {
        guard Permissions.shared.screenRecording else { return }

        var seen = Set<CGWindowID>()
        let targets: [(id: CGWindowID, frame: CGRect)] = items.compactMap { item in
            guard let id = item.previewWindowID, !seen.contains(id) else { return nil }
            seen.insert(id)
            return (id, item.frame)
        }

        captureTask?.cancel()
        cache = cache.filter { seen.contains($0.key) }

        captureTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false,
                                                                                      onScreenWindowsOnly: false)
            else { return }
            let scWindows = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })

            for target in targets {
                guard !Task.isCancelled else { return }
                guard let scWindow = scWindows[target.id] else { continue }

                let configuration = SCStreamConfiguration()
                let scale = min(1, Self.maxPixelSize / max(target.frame.width, target.frame.height, 1))
                configuration.width = max(1, Int(target.frame.width * scale))
                configuration.height = max(1, Int(target.frame.height * scale))
                configuration.showsCursor = false

                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                              configuration: configuration)
                else { continue }

                await MainActor.run {
                    self.cache[target.id] = image
                    onUpdate(target.id, image)
                }
            }
        }
    }

    func cancel() {
        captureTask?.cancel()
        captureTask = nil
    }
}
