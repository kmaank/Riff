import SwiftUI
import AppKit
import CoreText

enum RiffTheme {
    static let surface000 = Color(terminal: 0x06080A, paper: 0xEFECE4)
    static let surface100 = Color(terminal: 0x0C1013, paper: 0xFAF8F3)
    static let surface200 = Color(terminal: 0x12181D, paper: 0xFFFFFF)
    static let surface300 = Color(terminal: 0x1A222A, paper: 0xE6E2D8)
    static let line = Color(terminal: 0x232D36, paper: 0xD3CEC1)
    static let lineStrong = Color(terminal: 0x6A7883, paper: 0x7A7466)
    static let ink = Color(terminal: 0xEEF2F5, paper: 0x12161A)
    static let inkMuted = Color(terminal: 0x9AA8B3, paper: 0x4A545C)
    static let inkFaint = Color(terminal: 0x7D8B96, paper: 0x5B666E)
    static let amber = Color(terminal: 0xFF9F00, paper: 0xFF9F00)
    static let amberStrong = Color(terminal: 0xFFB733, paper: 0xE58A00)
    static let onAmber = Color(terminal: 0x0A0A0A, paper: 0x0A0A0A)
    static let amberInk = Color(terminal: 0xFF9F00, paper: 0x8A5300)
    static let amberWash = Color(terminal: 0xFF9F00, paper: 0x8A5300, terminalAlpha: 0.12, paperAlpha: 0.09)
    static let gain = Color(terminal: 0x22D47F, paper: 0x067A46)
    static let gainWash = Color(terminal: 0x22D47F, paper: 0x067A46, terminalAlpha: 0.12, paperAlpha: 0.06)
    static let loss = Color(terminal: 0xFF5C6C, paper: 0xC1202F)
    static let lossWash = Color(terminal: 0xFF5C6C, paper: 0xC1202F, terminalAlpha: 0.12, paperAlpha: 0.08)
    static let link = Color(terminal: 0x6CB6FF, paper: 0x0B5CAD)
    static let focus = Color(terminal: 0xFF9F00, paper: 0x8A5300)

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 24
    static let space6: CGFloat = 32
    static let space7: CGFloat = 48

    static let radiusXS: CGFloat = 2
    static let radiusSM: CGFloat = 4
    static let radiusMD: CGFloat = 10

    static let sidebarWidth: CGFloat = 220
    static let statusBarHeight: CGFloat = 28
    static let nsWindow = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return NSColor(srgbRed: 6 / 255, green: 8 / 255, blue: 10 / 255, alpha: 1)
        }
        return NSColor(srgbRed: 239 / 255, green: 236 / 255, blue: 228 / 255, alpha: 1)
    }

    static func applyAppearance(_ preference: String) {
        switch preference {
        case "terminal":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case "paper":
            NSApp.appearance = NSAppearance(named: .aqua)
        default:
            NSApp.appearance = nil
        }
        for window in NSApp.windows {
            window.appearance = NSApp.appearance
            window.backgroundColor = nsWindow
        }
    }
}

enum RiffType {
    static func display(_ size: CGFloat) -> Font {
        custom("IBM Plex Sans Condensed", size: size) ?? .system(size: size, weight: .bold, design: .default)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        custom("IBM Plex Sans", size: size) ?? .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat) -> Font {
        custom("IBM Plex Mono", size: size) ?? .system(size: size, weight: .medium, design: .monospaced)
    }

    static let displayXL = display(44)
    static let displayLG = display(28)
    static let h1 = sans(22, weight: .semibold)
    static let h2 = sans(16, weight: .semibold)
    static let body = sans(14)
    static let bodySM = sans(13)
    static let caption = sans(12)
    static let heroNum = sans(56, weight: .semibold)
    static let numXL = mono(40)
    static let numLG = mono(24)
    static let num = mono(13)
    static let label = mono(11)
    static let button = mono(12)

    private static func custom(_ name: String, size: CGFloat) -> Font? {
        NSFont(name: name, size: size) == nil ? nil : .custom(name, size: size)
    }
}

enum RiffFonts {
    static func register() {
        let names = [
            "IBMPlexSans-Regular",
            "IBMPlexSans-Medium",
            "IBMPlexSans-SemiBold",
            "IBMPlexSansCondensed-Bold",
            "IBMPlexMono-Medium",
            "IBMPlexMono-SemiBold"
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    init(terminal: UInt32, paper: UInt32, terminalAlpha: Double = 1, paperAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = dark ? terminal : paper
            let alpha = dark ? terminalAlpha : paperAlpha
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: CGFloat(alpha)
            )
        })
    }
}

enum RiffLogo {
    static func image(_ name: String) -> NSImage? {
        if let image = NSImage(named: name) { return image }
        if let path = Bundle.main.path(forResource: name, ofType: "png") {
            return NSImage(contentsOfFile: path)
        }
        return nil
    }

    static var wordmark: NSImage? { image("riff-wordmark") }
    static var appIcon: NSImage? { image("app_icon") ?? NSImage(named: "AppIcon") }
}

enum RiffDate {
    static func history(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .iso8601)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        var date: Date?
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        date = parser.date(from: iso)
        if date == nil {
            parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            date = parser.date(from: iso)
        }
        if date == nil {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            date = isoFormatter.date(from: iso)
        }
        guard let valid = date else {
            return iso.components(separatedBy: "T").last?.components(separatedBy: ".").first ?? iso
        }
        let display = DateFormatter()
        display.locale = Locale(identifier: "en_US_POSIX")
        display.timeZone = TimeZone(secondsFromGMT: 0)
        display.dateFormat = "dd MMM yyyy · HH:mm"
        return display.string(from: valid).uppercased()
    }
}

enum RiffScriptCopy {
    static func title(_ mode: String) -> String {
        switch mode {
        case "english_mixed": return "English Mixed"
        case "english_translated": return "English Translated"
        case "original_mixed": return "Original Mixed"
        default: return mode
        }
    }

    static func short(_ mode: String) -> String {
        switch mode {
        case "english_mixed": return "Eng-Mixed"
        case "english_translated": return "Translated"
        case "original_mixed": return "Original"
        default: return mode
        }
    }

    static func description(_ mode: String) -> String {
        switch mode {
        case "english_mixed": return "Keeps vernacular, romanizes non-English. Perfect for code-switching."
        case "english_translated": return "Translates everything to English. Clean, universal output."
        case "original_mixed": return "Auto-detects language and uses original script (Devanagari, etc.)."
        default: return ""
        }
    }

    static func example(_ mode: String) -> String {
        switch mode {
        case "english_mixed": return "Mujhe lagta hai we should meet"
        case "english_translated": return "I think we should meet"
        case "original_mixed": return "मुझे लगता है we should meet"
        default: return ""
        }
    }
}
