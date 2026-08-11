import SwiftUI

enum DockShelfTheme {
    static let accent = Color(nsColor: .controlAccentColor)
    static let itemBackground = Color(nsColor: .controlBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let invalid = Color(nsColor: .systemRed)
}

enum DockShelfMetrics {
    static let panelSize = CGSize(width: 420, height: 146)
    static let panelRadius: CGFloat = 20
    static let itemRadius: CGFloat = 12
    static let itemWidth: CGFloat = 68
    static let itemHeight: CGFloat = 94
    static let iconSize: CGFloat = 46
    static let itemSpacing: CGFloat = 8
    static let horizontalPadding: CGFloat = 16
}
