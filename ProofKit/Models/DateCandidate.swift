import Foundation

struct DateCandidate: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var source: DateSource
    var confidence: Double
    var label: String
    var rawValue: String?
    var detectedAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        source: DateSource,
        confidence: Double,
        label: String,
        rawValue: String? = nil,
        detectedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.source = source
        self.confidence = confidence
        self.label = label
        self.rawValue = rawValue
        self.detectedAt = detectedAt
    }

    static func encodeArray(_ candidates: [DateCandidate]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard
            let data = try? encoder.encode(candidates),
            let string = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return string
    }

    static func decodeArray(from jsonString: String) -> [DateCandidate] {
        guard let data = jsonString.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([DateCandidate].self, from: data)) ?? []
    }
}
