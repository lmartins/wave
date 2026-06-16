import Foundation

struct UsageStats: Codable, Equatable {
    var hourGrid: [String: Int] = [:]
    var dailyWords: [String: Int] = [:]
    var totalWords: Int = 0

    static let typingWPM = 40.0
    static let dictationWPM = 140.0

    static func gridKey(weekday: Int, hour: Int) -> String {
        "\(weekday)-\(hour)"
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    var estimatedTimeSavedSeconds: Int {
        let typingSecondsPerWord = 60.0 / Self.typingWPM
        let dictationSecondsPerWord = 60.0 / Self.dictationWPM
        let saved = Double(totalWords) * (typingSecondsPerWord - dictationSecondsPerWord)
        return max(0, Int(saved.rounded()))
    }

    mutating func record(words: Int, at date: Date, calendar: Calendar = .current) {
        guard words > 0 else { return }
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let gridKey = Self.gridKey(weekday: weekday, hour: hour)
        hourGrid[gridKey, default: 0] += words
        let dayKey = Self.dayKey(for: date, calendar: calendar)
        dailyWords[dayKey, default: 0] += words
        totalWords += words
    }

    mutating func mergeTakingMaximums(from other: UsageStats) {
        for (key, value) in other.hourGrid {
            hourGrid[key] = max(hourGrid[key] ?? 0, value)
        }
        for (key, value) in other.dailyWords {
            dailyWords[key] = max(dailyWords[key] ?? 0, value)
        }
        totalWords = max(max(totalWords, other.totalWords), dailyWords.values.reduce(0, +))
    }
}