import AppKit
import SwiftUI

/// Offline component render. No windows, screen capture, activation, or event injection.
@main struct ShelfAppearanceSmoke {
    @MainActor static func main() async throws {
        precondition(ShelfMotion.dropHold > ShelfMotion.unfold + ShelfMotion.settle)
        precondition(ShelfMotion.fold + ShelfMotion.exit > ShelfMotion.unfold)
        let managementBottom = DockShelfMetrics.tileTop + DockShelfMetrics.itemHeight
        let pageTop = DockShelfMetrics.contentHeight + (DockShelfMetrics.footerHeight - DockShelfMetrics.footerButtonSize) / 2
        precondition(pageTop - managementBottom >= 8, "Footer controls must not overlap file management")
        precondition(DockShelfMetrics.contentHeight + DockShelfMetrics.footerHeight == DockShelfMetrics.panelSize.height)
        var shown: [String] = []
        let first = Task { if await ShelfHoverTiming.ready(keyboardFocused: false) { shown.append("first") } }
        try await Task.sleep(for: .milliseconds(30))
        first.cancel()
        let second = Task { if await ShelfHoverTiming.ready(keyboardFocused: false) { shown.append("second") } }
        await first.value; await second.value
        precondition(shown == ["second"], "Fast hover switch cannot show the previous file")
        let focused = await ShelfHoverTiming.ready(keyboardFocused: true)
        precondition(focused, "Keyboard focus bypasses dwell")
        let kinds = ["jpg", "pdf", "zip", "mp3", "mov", "txt", "csv", "conf"].map {
            ShelfArtworkKind(url: URL(fileURLWithPath: "/fixture/example.\($0)"), isDirectory: false)
        }
        precondition(kinds[0].supportsPreview && kinds[1].supportsPreview && !kinds[2].supportsPreview)
        precondition(kinds[6].family == .spreadsheet && kinds[7].family == .code)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
          for receiving in [false, true] {
            let content = ZStack(alignment: .top) {
                LinearGradient(colors: scheme == .light ? [Color(red: 0.87, green: 0.91, blue: 0.88), Color(red: 0.96, green: 0.95, blue: 0.89)] : [Color(white: 0.13), Color(red: 0.13, green: 0.20, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                FoldingShelfMaterial(unfolded: true, reduceMotion: false, receiving: receiving).frame(height: 22).padding(.horizontal, 12).padding(.top, 92)
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(Array([kinds[6], kinds[7], kinds[0], kinds[2]].enumerated()), id: \.offset) { _, kind in
                        ShelfFileObject(kind: kind, preview: nil, hitLayer: EmptyView())
                    }
                }.padding(.top, 18)
                if !receiving {
                    ShelfHoverName(name: "11月采购清单_20261029.csv")
                        .padding(.bottom, 8)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }.frame(width: DockShelfMetrics.panelSize.width, height: DockShelfMetrics.panelSize.height).environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: content); renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Offscreen render failed") }
            let name = (scheme == .light ? "shelf-light" : "shelf-dark") + (receiving ? "-receiving" : "") + ".png"
            try png.write(to: output.appendingPathComponent(name))
          }
        }
        print("Appearance checks passed: footer separation, cancelled hover and focus, timing budget, preview eligibility, actual artwork/soft-touch surface offscreen renders in light and dark. UI acceptance remains manual.")
    }
}
