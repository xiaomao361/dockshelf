import SwiftUI

enum DockShelfTheme {
    static let accent = Color(nsColor: .controlAccentColor)
    static let itemBackground = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let invalid = Color(nsColor: .systemRed)
    static let warning = Color(nsColor: .systemOrange)
}

enum DockShelfMetrics {
    static let panelSize = CGSize(width: 420, height: 196)
    static let contentHeight: CGFloat = 156
    static let footerHeight: CGFloat = 40
    static let tileTop: CGFloat = 18
    static let footerButtonSize: CGFloat = 28
    static let panelRadius: CGFloat = 20
    static let itemRadius: CGFloat = 12
    static let itemWidth: CGFloat = 72
    static let itemHeight: CGFloat = 134
    static let iconSize: CGFloat = 64
    static let itemSpacing: CGFloat = 6
    static let horizontalPadding: CGFloat = 16
}

enum ShelfMotion {
    static let unfold: TimeInterval = 0.38
    static let settle: TimeInterval = 0.46
    static let dropHold: TimeInterval = 1.25
    static let fold: TimeInterval = 0.30
    static let exit: TimeInterval = 0.14
}

/// Fine matte soft-touch insert with a thin rigid edge, rather than polished metal.
struct FoldingShelfMaterial: View {
    @Environment(\.colorScheme) private var scheme
    let unfolded: Bool
    let reduceMotion: Bool
    var receiving: Bool = false
    private var dark: Bool { scheme == .dark }
    private var surface: Color { dark ? Color(red: 0.32, green: 0.35, blue: 0.33) : Color(red: 0.70, green: 0.72, blue: 0.69) }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(dark ? Color(white: 0.25) : Color(red: 0.56, green: 0.59, blue: 0.55))
                .frame(height: 1.5).padding(.horizontal, 8)
            ShelfDeckShape()
                .fill(LinearGradient(colors: [surface.opacity(0.97), surface], startPoint: .top, endPoint: .bottom))
                .overlay {
                    Canvas { context, size in
                        for index in 0..<1800 {
                            let x = CGFloat((index * 73 + index * index * 19) % 10007) / 10007 * size.width
                            let y = CGFloat((index * 191 + index * index * 7) % 9973) / 9973 * size.height
                            let dot = CGRect(x: x, y: y, width: 0.4, height: 0.35)
                            context.fill(Path(ellipseIn: dot), with: .color(index % 2 == 0 ? .white.opacity(0.045) : .black.opacity(0.025)))
                        }
                    }.clipShape(ShelfDeckShape())
                }
                .overlay {
                    ShelfDeckShape().fill(DockShelfTheme.accent.opacity(receiving ? 0.16 : 0))
                    ShelfDeckShape().stroke(receiving ? DockShelfTheme.accent.opacity(0.75) : .white.opacity(dark ? 0.10 : 0.22), lineWidth: receiving ? 1 : 0.5)
                    if receiving {
                        HStack {
                            ForEach(0..<5) { _ in
                                Image(systemName: "arrow.down.to.line.compact")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(DockShelfTheme.accent).frame(maxWidth: .infinity)
                            }
                        }.padding(.horizontal, 24)
                    }
                }
                .frame(height: 18)
            RoundedRectangle(cornerRadius: 1.2)
                .fill(dark ? Color(white: 0.34) : Color(red: 0.58, green: 0.61, blue: 0.57))
                .frame(height: 2.5)
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.25)).frame(height: 0.5) }
                .overlay { Capsule().fill(Color(red: 0.78, green: 0.65, blue: 0.46)).frame(width: 17, height: 1) }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.13), radius: 1.5, y: 1.5)
        .shadow(color: .black.opacity(0.13), radius: 7, y: 6)
        .rotation3DEffect(.degrees(unfolded || reduceMotion ? 0 : -86), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.4)
        .opacity(unfolded || reduceMotion ? 1 : 0)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// The narrower rear edge and wider front edge expose an upward-facing plane.
struct ShelfDeckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 7, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 7, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - 2), control: CGPoint(x: rect.maxX - 1, y: rect.minY + 4))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - 3, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + 3, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 2), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 7, y: rect.minY), control: CGPoint(x: rect.minX + 1, y: rect.minY + 4))
        path.closeSubpath()
        return path
    }
}

struct ShelfArtworkKind {
    enum Family { case photo, document, spreadsheet, code, archive, folder, audio, video }
    let family: Family
    let label: String
    var supportsPreview: Bool { family == .photo || label == "PDF" }
    var angle: Double { family == .photo ? -2.5 : (family == .archive ? -1.2 : 0.8) }

    init(url: URL, isDirectory: Bool) {
        let ext = url.pathExtension.lowercased()
        label = ext.isEmpty ? "FILE" : String(ext.uppercased().prefix(5))
        if isDirectory { family = .folder }
        else if ["jpg", "jpeg", "png", "heic", "webp", "gif", "tiff"].contains(ext) { family = .photo }
        else if ["csv", "tsv", "xlsx", "xls", "numbers"].contains(ext) { family = .spreadsheet }
        else if ["conf", "config", "json", "yaml", "yml", "toml", "ini", "xml", "swift", "py", "js", "ts", "sh", "css", "html"].contains(ext) { family = .code }
        else if ["zip", "rar", "7z", "gz", "tar"].contains(ext) { family = .archive }
        else if ["mp3", "wav", "m4a", "flac", "aiff"].contains(ext) { family = .audio }
        else if ["mp4", "mov", "m4v", "avi"].contains(ext) { family = .video }
        else { family = .document }
    }
}

/// Shared by the shelf and native drag image, so pickup never changes silhouette.
struct ShelfFileArtwork: View {
    let kind: ShelfArtworkKind
    let preview: NSImage?
    private var paper: Color {
        switch kind.family {
        case .spreadsheet: Color(red: 0.93, green: 0.96, blue: 0.92)
        case .code: Color(red: 0.93, green: 0.95, blue: 0.97)
        case .archive: Color(red: 0.97, green: 0.94, blue: 0.86)
        default: Color(red: 0.98, green: 0.97, blue: 0.94)
        }
    }
    private var ink: Color {
        switch kind.family {
        case .spreadsheet: Color(red: 0.36, green: 0.53, blue: 0.42)
        case .code: Color(red: 0.36, green: 0.47, blue: 0.61)
        case .archive: Color(red: 0.55, green: 0.44, blue: 0.28)
        case .audio: Color(red: 0.51, green: 0.43, blue: 0.60)
        default: Color(red: 0.47, green: 0.52, blue: 0.54)
        }
    }

    var body: some View {
        Group {
            if kind.family == .folder { folder }
            else if kind.family == .photo { photo }
            else { document }
        }
        .rotationEffect(.degrees(kind.family == .folder ? 0 : kind.angle), anchor: .bottom)
        .frame(width: 64, height: 78, alignment: .bottom)
        .compositingGroup()
        .accessibilityHidden(true)
    }

    private var photo: some View {
        VStack(spacing: 0) {
            Group {
                if let preview { Image(nsImage: preview).resizable().scaledToFill() }
                else { Image(systemName: "photo").font(.system(size: 23, weight: .light)).foregroundStyle(ink).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.77, green: 0.85, blue: 0.82)) }
            }
            .frame(width: 52, height: 62).clipped().clipShape(RoundedRectangle(cornerRadius: 2))
            Spacer(minLength: 0)
        }
        .padding(5).frame(width: 62, height: 78)
        .background(LinearGradient(colors: [.white, paper], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(.black.opacity(0.10), lineWidth: 0.5) }
    }

    private var folder: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.48, green: 0.72, blue: 0.78))
                .frame(width: 30, height: 14).offset(x: -16, y: -42)
            RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.42, green: 0.66, blue: 0.74)).frame(width: 64, height: 50)
            RoundedRectangle(cornerRadius: 2).fill(paper).frame(width: 53, height: 39).offset(y: -7).rotationEffect(.degrees(-3))
            RoundedRectangle(cornerRadius: 5)
                .fill(LinearGradient(colors: [Color(red: 0.72, green: 0.87, blue: 0.89), Color(red: 0.39, green: 0.66, blue: 0.73)], startPoint: .top, endPoint: .bottom))
                .frame(width: 64, height: 43)
                .overlay(alignment: .top) { RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.6)).frame(height: 1).padding(.horizontal, 3) }
        }
        .frame(width: 64, height: 60)
    }

    private var document: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [.white, paper], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let preview, kind.label == "PDF" {
                Image(nsImage: preview).resizable().scaledToFit().padding(5).padding(.bottom, 14)
            } else if kind.family == .spreadsheet {
                VStack(spacing: 0) {
                    Rectangle().fill(ink.opacity(0.28)).frame(height: 6)
                    ForEach(0..<4) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<3) { column in
                                Rectangle().fill(ink.opacity(column == 0 ? 0.10 : 0.025))
                                    .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.19)).frame(height: 0.5) }
                                    .overlay(alignment: .trailing) { Rectangle().fill(ink.opacity(0.19)).frame(width: 0.5) }
                            }
                        }.frame(height: 6)
                    }
                }.frame(width: 36).clipShape(RoundedRectangle(cornerRadius: 1.5)).padding(.leading, 10).padding(.top, 13)
            } else if kind.family == .code {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<5) { row in
                        HStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 0.5).fill(ink.opacity(0.45)).frame(width: row % 2 == 0 ? 8 : 5, height: 2)
                            RoundedRectangle(cornerRadius: 0.5).fill(ink.opacity(0.22)).frame(width: row % 3 == 0 ? 13 : 18, height: 2)
                        }.padding(.leading, row == 1 || row == 2 ? 5 : 0)
                    }
                }.padding(.leading, 10).padding(.top, 15)
            } else if kind.family == .archive {
                VStack(spacing: 1.5) {
                    ForEach(0..<7) { i in
                        RoundedRectangle(cornerRadius: 0.5).fill(ink.opacity(i % 2 == 0 ? 0.55 : 0.3)).frame(width: 5, height: 3).offset(x: i % 2 == 0 ? -1.5 : 1.5)
                    }
                }.frame(maxWidth: .infinity).padding(.top, 3)
                RoundedRectangle(cornerRadius: 2).stroke(ink.opacity(0.8), lineWidth: 2).frame(width: 8, height: 13).offset(x: 23, y: 27)
            } else if kind.family == .audio || kind.family == .video {
                Image(systemName: kind.family == .audio ? "waveform" : "play.rectangle")
                    .font(.system(size: 22, weight: .light)).foregroundStyle(ink.opacity(0.8))
                    .frame(maxWidth: .infinity).padding(.top, 17)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 1).fill(ink.opacity(0.45)).frame(width: 23, height: 3)
                    ForEach(0..<3) { i in Capsule().fill(ink.opacity(0.18)).frame(width: i == 2 ? 22 : 34, height: 2) }
                }.padding(.leading, 9).padding(.top, 15)
            }
            Text(kind.label).font(.system(size: 9, weight: .medium, design: .rounded))
                .tracking(0.5).foregroundStyle(ink)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(ink.opacity(0.075), in: RoundedRectangle(cornerRadius: 2))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 7)
            Path { p in p.move(to: CGPoint(x: 43, y: 0)); p.addLine(to: CGPoint(x: 56, y: 13)); p.addLine(to: CGPoint(x: 43, y: 13)); p.closeSubpath() }
                .fill(LinearGradient(colors: [ink.opacity(0.16), .white.opacity(0.8)], startPoint: .bottomLeading, endPoint: .topTrailing))
        }
        .frame(width: 56, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(.black.opacity(0.12), lineWidth: 0.5) }
    }
}

struct ShelfHoverName: View {
    let name: String
    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.primary.opacity(0.86))
            .lineLimit(1).truncationMode(.middle)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .frame(maxWidth: 300)
            .allowsHitTesting(false)
            .accessibilityLabel(name)
    }
}


/// A cancelled pointer dwell never becomes a late label update.
enum ShelfHoverTiming {
    static func ready(keyboardFocused: Bool) async -> Bool {
        if !keyboardFocused {
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return false }
        }
        return !Task.isCancelled
    }
}

/// Contact stays on the plane; artwork and its native hit layer move together above it.
struct ShelfFileObject<HitLayer: View>: View {
    let kind: ShelfArtworkKind
    let preview: NSImage?
    var lifted = false
    var opacity: Double = 1
    var dragging = false
    let hitLayer: HitLayer
    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse().fill(.black.opacity(dragging ? 0.03 : (lifted ? 0.09 : 0.15)))
                .frame(width: lifted ? 36 : 34, height: 2.5)
                .blur(radius: lifted ? 2 : 0.8).offset(y: 1)
            ShelfFileArtwork(kind: kind, preview: preview)
                .shadow(color: .black.opacity(lifted ? 0.14 : 0.10), radius: lifted ? 2.5 : 0.8, y: lifted ? 2 : 0.5)
                .overlay { hitLayer }
                .offset(y: lifted ? -4 : 0)
                .opacity(opacity)
        }.frame(width: 64, height: 78)
    }
}
