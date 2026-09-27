import Foundation

enum RiffHotkey {
    static func displayName(_ combination: String) -> String {
        switch combination {
        case "ctrl_l": return "Left Control"
        case "ctrl_r": return "Right Control"
        case "alt_l": return "Left Option"
        case "alt_r": return "Right Option"
        case "cmd_l": return "Left Command"
        case "cmd_r": return "Right Command"
        case "f1": return "F1"
        case "f2": return "F2"
        case "f3": return "F3"
        case "f4": return "F4"
        case "f5": return "F5"
        case "f6": return "F6"
        case "f7": return "F7"
        case "f8": return "F8"
        case "f9": return "F9"
        case "f10": return "F10"
        case "f11": return "F11"
        case "f12": return "F12"
        default: return combination
        }
    }

    static func holdPrompt(_ combination: String) -> String {
        "Hold \(displayName(combination))"
    }

    static func keycap(_ combination: String) -> String {
        switch combination {
        case "ctrl_l": return "L-CTRL"
        case "ctrl_r": return "R-CTRL"
        case "alt_l": return "L-OPT"
        case "alt_r": return "R-OPT"
        case "cmd_l": return "L-CMD"
        case "cmd_r": return "R-CMD"
        case "f1": return "F1"
        case "f2": return "F2"
        case "f3": return "F3"
        case "f4": return "F4"
        case "f5": return "F5"
        case "f6": return "F6"
        case "f7": return "F7"
        case "f8": return "F8"
        case "f9": return "F9"
        case "f10": return "F10"
        case "f11": return "F11"
        case "f12": return "F12"
        default: return displayName(combination).uppercased()
        }
    }
}

enum RiffStyleCopy {
    static func promise(_ style: String) -> String {
        switch style {
        case "casual": return "Fastest — pasted as you said it"
        case "clean": return "Tidies filler, keeps your words"
        case "formal": return "Email-ready polish"
        case "riff": return "Answers you, like a friend"
        default: return ""
        }
    }
}

struct HudStatus: Codable {
    var state: String = "hidden"
    var style: String? = nil
    var message: String? = nil
    var elapsed: Double? = nil
}
