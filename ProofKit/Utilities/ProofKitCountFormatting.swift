import Foundation

extension Int {
    var evidenceItemCountText: String {
        self == 1 ? "1 evidence item" : "\(self) evidence items"
    }
}
