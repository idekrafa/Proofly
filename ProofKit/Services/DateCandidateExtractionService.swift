import Foundation
import ImageIO

protocol DateCandidateExtracting {
    func extractDateCandidates(
        imageFileURL: URL,
        originalFilename: String,
        importedAt: Date,
        ocrText: String
    ) async -> [DateCandidate]

    func bestDefaultEventDateCandidate(from candidates: [DateCandidate]) -> DateCandidate?
}

struct DateCandidateExtractionService: DateCandidateExtracting {
    func extractDateCandidates(
        imageFileURL: URL,
        originalFilename: String,
        importedAt: Date,
        ocrText: String
    ) async -> [DateCandidate] {
        var candidates: [DateCandidate] = []

        candidates.append(contentsOf: imageMetadataCandidates(from: imageFileURL))
        candidates.append(contentsOf: filenameCandidates(from: originalFilename))
        candidates.append(contentsOf: ocrCandidates(from: ocrText))
        candidates.append(
            DateCandidate(
                date: importedAt,
                source: .importedMetadata,
                confidence: 0.35,
                label: "Imported into Proofly",
                rawValue: ISO8601DateFormatter().string(from: importedAt)
            )
        )

        return uniquedAndSorted(candidates)
    }

    func bestDefaultEventDateCandidate(from candidates: [DateCandidate]) -> DateCandidate? {
        uniquedAndSorted(candidates).first
    }

    private func imageMetadataCandidates(from imageFileURL: URL) -> [DateCandidate] {
        guard
            imageFileURL.isFileURL,
            FileManager.default.fileExists(atPath: imageFileURL.path(percentEncoded: false)),
            let imageSource = CGImageSourceCreateWithURL(imageFileURL as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any]
        else {
            return []
        }

        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let metadataFields: [(dictionary: [String: Any]?, key: String, label: String, confidence: Double)] = [
            (
                exif,
                kCGImagePropertyExifDateTimeOriginal as String,
                "Original image creation date",
                0.96
            ),
            (
                exif,
                kCGImagePropertyExifDateTimeDigitized as String,
                "Digitized image date",
                0.86
            ),
            (
                tiff,
                kCGImagePropertyTIFFDateTime as String,
                "Image metadata date",
                0.80
            )
        ]

        return metadataFields.compactMap { field in
            guard
                let rawValue = field.dictionary?[field.key] as? String,
                let date = parseMetadataDate(rawValue)
            else {
                return nil
            }

            return DateCandidate(
                date: date,
                source: .fileMetadata,
                confidence: field.confidence,
                label: field.label,
                rawValue: rawValue
            )
        }
    }

    private func filenameCandidates(from originalFilename: String) -> [DateCandidate] {
        let nameWithoutExtension = URL(filePath: originalFilename)
            .deletingPathExtension()
            .lastPathComponent

        return parseExplicitDatePatterns(in: nameWithoutExtension).map { parsedDate in
            DateCandidate(
                date: parsedDate.date,
                source: .filename,
                confidence: parsedDate.isCompactFilenameDate ? 0.72 : 0.76,
                label: "Date found in filename",
                rawValue: parsedDate.rawValue
            )
        }
    }

    private func ocrCandidates(from ocrText: String) -> [DateCandidate] {
        let trimmedText = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return [] }

        var candidates = parseExplicitDatePatterns(in: trimmedText).map { parsedDate in
            DateCandidate(
                date: parsedDate.date,
                source: .visionOCR,
                confidence: parsedDate.hasFourDigitYear ? 0.74 : 0.62,
                label: "Date found in OCR text",
                rawValue: parsedDate.rawValue
            )
        }

        candidates.append(contentsOf: dataDetectorCandidates(from: trimmedText))
        return candidates
    }

    private func dataDetectorCandidates(from text: String) -> [DateCandidate] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return detector.matches(in: text, options: [], range: fullRange).compactMap { match in
            guard let date = match.date else { return nil }

            let rawValue = nsText.substring(with: match.range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard looksLikeCalendarDate(rawValue) else {
                return nil
            }

            return DateCandidate(
                date: normalizedDateIfDateOnly(date, rawValue: rawValue),
                source: .visionOCR,
                confidence: rawValueContainsFourDigitYear(rawValue) ? 0.70 : 0.52,
                label: "Date found in OCR text",
                rawValue: rawValue
            )
        }
    }

    private func parseMetadataDate(_ rawValue: String) -> Date? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        if let isoDate = isoFormatter.date(from: trimmedValue) {
            return isoDate
        }

        let formats = [
            "yyyy:MM:dd HH:mm:ss",
            "yyyy:MM:dd HH:mm:ss.SSS",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = gregorianCalendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateFormat = format

            if let date = formatter.date(from: trimmedValue) {
                return date
            }
        }

        return nil
    }

    private func parseExplicitDatePatterns(in text: String) -> [ParsedDateCandidate] {
        var parsedDates: [ParsedDateCandidate] = []

        parsedDates.append(
            contentsOf: regexMatches(
                in: text,
                pattern: #"\b((?:19|20)\d{2})[-_./](0?[1-9]|1[0-2])[-_./](0?[1-9]|[12]\d|3[01])\b"#
            ).compactMap { match in
                guard
                    let year = Int(match.captureGroups[0]),
                    let month = Int(match.captureGroups[1]),
                    let day = Int(match.captureGroups[2]),
                    let date = dateFrom(year: year, month: month, day: day)
                else {
                    return nil
                }

                return ParsedDateCandidate(
                    date: date,
                    rawValue: match.rawValue,
                    hasFourDigitYear: true,
                    isCompactFilenameDate: false
                )
            }
        )

        parsedDates.append(
            contentsOf: regexMatches(
                in: text,
                pattern: #"\b(0?[1-9]|1[0-2])[-_./](0?[1-9]|[12]\d|3[01])[-_./]((?:19|20)?\d{2})\b"#
            ).compactMap { match in
                guard
                    let month = Int(match.captureGroups[0]),
                    let day = Int(match.captureGroups[1]),
                    let year = normalizedYear(from: match.captureGroups[2]),
                    let date = dateFrom(year: year, month: month, day: day)
                else {
                    return nil
                }

                return ParsedDateCandidate(
                    date: date,
                    rawValue: match.rawValue,
                    hasFourDigitYear: match.captureGroups[2].count == 4,
                    isCompactFilenameDate: false
                )
            }
        )

        parsedDates.append(
            contentsOf: regexMatches(
                in: text,
                pattern: #"\b((?:19|20)\d{2})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])\b"#
            ).compactMap { match in
                guard
                    let year = Int(match.captureGroups[0]),
                    let month = Int(match.captureGroups[1]),
                    let day = Int(match.captureGroups[2]),
                    let date = dateFrom(year: year, month: month, day: day)
                else {
                    return nil
                }

                return ParsedDateCandidate(
                    date: date,
                    rawValue: match.rawValue,
                    hasFourDigitYear: true,
                    isCompactFilenameDate: true
                )
            }
        )

        parsedDates.append(contentsOf: monthNameMatches(in: text))
        return parsedDates
    }

    private func monthNameMatches(in text: String) -> [ParsedDateCandidate] {
        regexMatches(
            in: text,
            pattern: #"\b(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+([0-3]?\d)(?:st|nd|rd|th)?,?\s+((?:19|20)\d{2})\b"#
        ).compactMap { match in
            guard
                let month = monthNumber(from: match.captureGroups[0]),
                let day = Int(match.captureGroups[1]),
                let year = Int(match.captureGroups[2]),
                let date = dateFrom(year: year, month: month, day: day)
            else {
                return nil
            }

            return ParsedDateCandidate(
                date: date,
                rawValue: match.rawValue,
                hasFourDigitYear: true,
                isCompactFilenameDate: false
            )
        }
    }

    private func regexMatches(in text: String, pattern: String) -> [RegexMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, options: [], range: fullRange).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }

            var captureGroups: [String] = []
            for index in 1..<match.numberOfRanges {
                let captureRange = match.range(at: index)
                guard captureRange.location != NSNotFound else {
                    captureGroups.append("")
                    continue
                }
                captureGroups.append(nsText.substring(with: captureRange))
            }

            return RegexMatch(
                rawValue: nsText.substring(with: match.range),
                captureGroups: captureGroups
            )
        }
    }

    private func normalizedYear(from rawYear: String) -> Int? {
        guard let year = Int(rawYear) else { return nil }

        if rawYear.count == 2 {
            return year >= 70 ? 1900 + year : 2000 + year
        }

        return year
    }

    private func dateFrom(year: Int, month: Int, day: Int) -> Date? {
        guard (1900...2100).contains(year) else { return nil }

        var components = DateComponents()
        components.calendar = gregorianCalendar
        components.timeZone = .autoupdatingCurrent
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.minute = 0
        components.second = 0

        guard let date = gregorianCalendar.date(from: components) else {
            return nil
        }

        return gregorianCalendar.component(.year, from: date) == year &&
            gregorianCalendar.component(.month, from: date) == month &&
            gregorianCalendar.component(.day, from: date) == day
            ? date
            : nil
    }

    private func normalizedDateIfDateOnly(_ date: Date, rawValue: String) -> Date {
        guard rawValue.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) == nil else {
            return date
        }

        let dateComponents = gregorianCalendar.dateComponents([.year, .month, .day], from: date)
        guard
            let year = dateComponents.year,
            let month = dateComponents.month,
            let day = dateComponents.day
        else {
            return date
        }

        return dateFrom(year: year, month: month, day: day) ?? date
    }

    private func looksLikeCalendarDate(_ rawValue: String) -> Bool {
        rawValue.range(of: #"\d{1,4}[-_./]\d{1,2}[-_./]\d{1,4}"#, options: .regularExpression) != nil ||
            rawValue.range(
                of: #"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
    }

    private func rawValueContainsFourDigitYear(_ rawValue: String) -> Bool {
        rawValue.range(of: #"\b(?:19|20)\d{2}\b"#, options: .regularExpression) != nil
    }

    private func monthNumber(from rawMonth: String) -> Int? {
        switch rawMonth.lowercased().prefix(3) {
        case "jan": 1
        case "feb": 2
        case "mar": 3
        case "apr": 4
        case "may": 5
        case "jun": 6
        case "jul": 7
        case "aug": 8
        case "sep": 9
        case "oct": 10
        case "nov": 11
        case "dec": 12
        default: nil
        }
    }

    private func uniquedAndSorted(_ candidates: [DateCandidate]) -> [DateCandidate] {
        var seenKeys = Set<String>()
        var uniqueCandidates: [DateCandidate] = []

        for candidate in candidates.sorted(by: isHigherPriority) {
            let key = uniquenessKey(for: candidate)
            guard !seenKeys.contains(key) else { continue }

            seenKeys.insert(key)
            uniqueCandidates.append(candidate)
        }

        return uniqueCandidates
    }

    private func uniquenessKey(for candidate: DateCandidate) -> String {
        let dateComponents = gregorianCalendar.dateComponents([.year, .month, .day], from: candidate.date)
        let dayKey = [
            dateComponents.year.map(String.init) ?? "0000",
            dateComponents.month.map(String.init) ?? "00",
            dateComponents.day.map(String.init) ?? "00"
        ].joined(separator: "-")

        return [
            candidate.source.rawValue,
            dayKey,
            candidate.rawValue?.lowercased() ?? ""
        ].joined(separator: "|")
    }

    private func isHigherPriority(_ lhs: DateCandidate, than rhs: DateCandidate) -> Bool {
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }

        let lhsRank = sourceRank(lhs.source)
        let rhsRank = sourceRank(rhs.source)
        if lhsRank != rhsRank {
            return lhsRank > rhsRank
        }

        return lhs.date > rhs.date
    }

    private func sourceRank(_ source: DateSource) -> Int {
        switch source {
        case .fileMetadata:
            5
        case .visionOCR:
            4
        case .filename:
            3
        case .importedMetadata:
            2
        case .userEntered:
            1
        case .aiSuggested, .notSpecified:
            0
        }
    }

    private var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }
}

private struct ParsedDateCandidate {
    let date: Date
    let rawValue: String
    let hasFourDigitYear: Bool
    let isCompactFilenameDate: Bool
}

private struct RegexMatch {
    let rawValue: String
    let captureGroups: [String]
}
