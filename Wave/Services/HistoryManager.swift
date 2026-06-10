import Foundation

@Observable
final class HistoryManager {
    private(set) var records: [TranscriptionRecord] = []
    private var usageStats = UsageStats()

    init() {
        load()
        backfillUsageFromRecords()
    }

    func add(_ text: String) {
        let record = TranscriptionRecord(id: UUID(), text: text, date: Date())
        records.insert(record, at: 0)
        if records.count > 50 { records = Array(records.prefix(50)) }
        usageStats.record(words: record.wordCount, at: record.date)
        save()
        saveUsage()
    }

    func remove(_ id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        records.removeAll()
        save()
    }

    var wordsToday: Int {
        let key = UsageStats.dayKey(for: Date())
        return usageStats.dailyWords[key] ?? records.filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.wordCount }
    }

    var wordsThisWeek: Int {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date()))!
        return usageStats.dailyWords.reduce(0) { total, entry in
            guard let date = Self.date(fromDayKey: entry.key), date >= start else { return total }
            return total + entry.value
        }
    }

    var totalWords: Int { usageStats.totalWords }

    var estimatedTimeSavedSeconds: Int { usageStats.estimatedTimeSavedSeconds }

    var activityHeatmap: [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        for weekday in 1...7 {
            for hour in 0..<24 {
                let key = UsageStats.gridKey(weekday: weekday, hour: hour)
                grid[weekday - 1][hour] = usageStats.hourGrid[key] ?? 0
            }
        }
        return grid
    }

    var activityHeatmapMax: Int {
        activityHeatmap.flatMap { $0 }.max() ?? 0
    }

    var wordsLast7Days: [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return 0 }
            return usageStats.dailyWords[UsageStats.dayKey(for: date)] ?? 0
        }
    }

    var wordsLast7DayLabels: [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return (0..<7).reversed().map { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return "" }
            return formatter.string(from: date)
        }
    }

    var wordsLast7DaysMax: Int {
        wordsLast7Days.max() ?? 0
    }

    private func backfillUsageFromRecords() {
        guard usageStats.totalWords == 0, !records.isEmpty else { return }
        for record in records {
            usageStats.record(words: record.wordCount, at: record.date)
        }
        saveUsage()
    }

    private static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: "transcriptionHistory")
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: "transcriptionHistory"),
           let decoded = try? JSONDecoder().decode([TranscriptionRecord].self, from: data) {
            records = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "usageStats"),
           let decoded = try? JSONDecoder().decode(UsageStats.self, from: data) {
            usageStats = decoded
        }
    }

    private func saveUsage() {
        if let data = try? JSONEncoder().encode(usageStats) {
            UserDefaults.standard.set(data, forKey: "usageStats")
        }
    }
}