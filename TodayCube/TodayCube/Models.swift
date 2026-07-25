import SwiftUI

enum Mode: String, CaseIterable, Codable {
    case deepWork, move, create, social, rest, admin

    // Matches the physical die: face index 0–5 in this order.
    static func fromFaceIndex(_ index: Int) -> Mode? {
        guard Mode.allCases.indices.contains(index) else { return nil }
        return Mode.allCases[index]
    }

    var pipCount: Int {
        switch self {
        case .deepWork: return 1
        case .move: return 2
        case .create: return 3
        case .social: return 4
        case .rest: return 5
        case .admin: return 6
        }
    }

    var displayName: String {
        switch self {
        case .deepWork: return "Deep Work"
        case .move: return "Move"
        case .create: return "Create"
        case .social: return "Social"
        case .rest: return "Rest"
        case .admin: return "Admin"
        }
    }

    var color: Color {
        switch self {
        case .deepWork: return Color(hex: 0x3987E5)
        case .move: return Color(hex: 0xD95926)
        case .create: return Color(hex: 0xD55181)
        case .social: return Color(hex: 0xC98500)
        case .rest: return Color(hex: 0x199E70)
        case .admin: return Color(hex: 0x9085E9)
        }
    }

    var accessoryName: String {
        switch self {
        case .deepWork: return "Book"
        case .move: return "Sneaker"
        case .create: return "Brush"
        case .social: return "Speech bubble"
        case .rest: return "Blanket"
        case .admin: return "Clipboard"
        }
    }
}

struct DayLog: Codable, Identifiable {
    let id: UUID
    let date: Date
    var mode: Mode?
}
