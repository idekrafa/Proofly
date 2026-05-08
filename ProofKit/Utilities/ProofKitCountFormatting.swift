import Foundation

extension Int {
    var evidenceItemCountText: String {
        self == 1 ? "1 proof item" : "\(self) proof items"
    }
}
