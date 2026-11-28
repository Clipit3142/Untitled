/// Spacing scale. Views take every distance from here (design-system rules).
public enum Spacing {
    public static let xxs: Double = 2
    public static let xs: Double = 4
    public static let s: Double = 8
    public static let m: Double = 12
    public static let l: Double = 16
    public static let xl: Double = 24
    public static let xxl: Double = 32
}

/// Corner radius scale.
public enum Radius {
    public static let s: Double = 6
    public static let m: Double = 10
    public static let panel: Double = 18
    public static let thumbnail: Double = 4
}

/// Fixed sizes from 3.15.
public enum Metrics {
    public static let menuBarPanelWidth: Double = 360
    public static let quickRenameWidth: Double = 520
    public static let mainWindowMinWidth: Double = 880
    public static let mainWindowMinHeight: Double = 580
    public static let rowThumbnail: Double = 32
    public static let inspectorPreview: Double = 220
    public static let recentCount = 5
    public static let statusGlyphSize: Double = 18
    /// The panel keeps this distance from every screen edge (N2).
    public static let screenMargin: Double = 8
    /// The gap between the menu bar and the panel.
    public static let panelGap: Double = 4
}
