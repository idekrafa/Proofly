import Foundation

extension Int {
    var evidenceItemCountText: String {
        self == 1 ? String(localized: "1 proof item") : String(localized: "\(self) proof items")
    }
}
