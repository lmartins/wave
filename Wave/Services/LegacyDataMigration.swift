import Foundation

enum LegacyDataMigration {
    private struct LegacyPreferences {
        let bundleID: String
        let values: [String: Any]
    }

    private static let migratedKey = "didMigrateFromLegacyApps"
    private static let supplementedUsageStatsKey = "didSupplementLegacyUsageStats"
    private static let canonicalDebugBundleID = "\(AppIdentity.bundleID).debug"

    private static let legacyReleaseBundleIDs = [
        "io.monawwar.wave",
        "com.starbubbles.swell",
        "com.shuttleworks.Swell",
        "app.useloqui.Loqui",
    ]
    private static let legacyDebugBundleIDs = [
        "io.monawwar.wave.debug",
        "com.starbubbles.swell.debug",
        "com.shuttleworks.Swell.debug",
        "app.useloqui.Loqui.debug",
        canonicalDebugBundleID,
    ]
    private static let legacyModelsPaths = [
        "app.useloqui.Loqui.debug/models",
        "app.useloqui.Loqui/models",
        "com.shuttleworks.Swell.debug/models",
        "com.shuttleworks.Swell/models",
        "com.starbubbles.swell.debug/models",
        "com.starbubbles.swell/models",
        "io.monawwar.wave/models",
    ]

    private static let settingsKeys = [
        "isOnboardingComplete", "dictationMode", "hotkeyKeyCode", "hotkeyModifiers",
        "includePunctuation", "muteSystemAudio", "hideIdlePill", "showInDock",
        "customVocabulary", "transcriptionProvider", "groqAPIKey", "groqModel",
        "transcriptionLanguage", "selectedMicUID", "whisperPrompt", "llmSystemPrompt",
        "aiModeKeyCode", "aiModeModifiers", "cancelHotkeyKeyCode", "cancelHotkeyModifiers",
        "pasteLastHotkeyKeyCode", "pasteLastHotkeyModifiers", "aiModel", "groqFetchedModels",
        "selectedModelPath", "snippets",
        "usagePromptTokens", "usageCompletionTokens", "usageTotalTokens",
        "usageTotalTime", "usageRequestCount",
        "modes", "activeModeId",
        "stripFillerWords", "silenceAutoStop", "useAppAwareModes",
        "appModeMappings", "appRules", "useFastLocalFormatting",
    ]

    static func migrateIfNeeded() {
        ensureModelsDirectory()
        repairSelectedModelPath()

        if !UserDefaults.standard.bool(forKey: migratedKey) {
            migrateLegacyData()
            repairSelectedModelPath()
            UserDefaults.standard.set(true, forKey: migratedKey)
            UserDefaults.standard.set(true, forKey: supplementedUsageStatsKey)
            return
        }

        if !UserDefaults.standard.bool(forKey: supplementedUsageStatsKey) {
            migrateLegacyData()
            repairSelectedModelPath()
            UserDefaults.standard.set(true, forKey: supplementedUsageStatsKey)
        }
    }

    static func ensureModelsDirectory() {
        migrateModelsDirectory()
    }

    static func mergeUsageStats(into current: UsageStats, from legacyData: Data?) -> UsageStats {
        guard let legacyData,
              let legacy = try? JSONDecoder().decode(UsageStats.self, from: legacyData) else {
            return current
        }
        var merged = current
        merged.mergeTakingMaximums(from: legacy)
        return merged
    }

    static func mergeHistory(from legacyData: Data?, into current: [TranscriptionRecord]) -> [TranscriptionRecord] {
        guard let legacyData,
              let legacy = try? JSONDecoder().decode([TranscriptionRecord].self, from: legacyData) else {
            return current
        }
        var seen = Set(current.map(\.id))
        var merged = current
        for record in legacy where !seen.contains(record.id) {
            merged.append(record)
            seen.insert(record.id)
        }
        return merged.sorted { $0.date > $1.date }.prefix(50).map { $0 }
    }

    private static func migrateLegacyData() {
        let currentBundle = Bundle.main.bundleIdentifier ?? AppIdentity.bundleID
        let sources = legacyPreferences(excluding: currentBundle)
        migrateUsageStats(from: sources)
        migrateHistory(from: sources)
        migrateSettings(from: sources)
    }

    private static func legacyPreferences(excluding currentBundle: String) -> [LegacyPreferences] {
        activeLegacyBundleIDs()
            .filter { $0 != currentBundle }
            .map { LegacyPreferences(bundleID: $0, values: legacyPreferences(for: $0)) }
            .filter { !$0.values.isEmpty }
    }

    private static func activeLegacyBundleIDs() -> [String] {
        var seen = Set<String>()
        return (legacyReleaseBundleIDs + legacyDebugBundleIDs).filter { seen.insert($0).inserted }
    }

    private static func legacyPreferences(for bundleID: String) -> [String: Any] {
        CFPreferencesCopyMultiple(
            nil,
            bundleID as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String: Any] ?? [:]
    }

    private static func migrateUsageStats(from sources: [LegacyPreferences]) {
        var current = UserDefaults.standard.data(forKey: "usageStats")
            .flatMap { try? JSONDecoder().decode(UsageStats.self, from: $0) } ?? UsageStats()

        for source in sources where !shouldSkipUsageStats(from: source) {
            guard let legacyData = source.values["usageStats"] as? Data,
                  let legacy = try? JSONDecoder().decode(UsageStats.self, from: legacyData) else { continue }
            current.mergeTakingMaximums(from: legacy)
        }

        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: "usageStats")
        }
    }

    private static func shouldSkipUsageStats(from source: LegacyPreferences) -> Bool {
        source.bundleID == canonicalDebugBundleID
            && source.values[migratedKey] as? Bool == true
            && source.values[supplementedUsageStatsKey] as? Bool == true
    }

    private static func migrateHistory(from sources: [LegacyPreferences]) {
        var current = UserDefaults.standard.data(forKey: "transcriptionHistory")
            .flatMap { try? JSONDecoder().decode([TranscriptionRecord].self, from: $0) } ?? []

        for source in sources {
            current = mergeHistory(from: source.values["transcriptionHistory"] as? Data, into: current)
        }

        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: "transcriptionHistory")
        }
    }

    private static func migrateSettings(from sources: [LegacyPreferences]) {
        for key in settingsKeys where UserDefaults.standard.object(forKey: key) == nil {
            guard let value = sources.reversed().compactMap({ $0.values[key] }).first else { continue }
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    private static func repairSelectedModelPath() {
        guard let path = UserDefaults.standard.string(forKey: "selectedModelPath") else { return }
        if FileManager.default.fileExists(atPath: path) { return }
        let filename = URL(fileURLWithPath: path).lastPathComponent
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        let localPath = appSupport.appendingPathComponent("\(bundleID)/models/\(filename)").path
        if FileManager.default.fileExists(atPath: localPath) {
            UserDefaults.standard.set(localPath, forKey: "selectedModelPath")
        }
    }

    private static func migrateModelsDirectory() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier else { return }

        let newDir = appSupport.appendingPathComponent("\(bundleID)/models")
        if hasModelFiles(at: newDir) { return }

        for relativePath in legacyModelsPaths {
            let legacyDir = appSupport.appendingPathComponent(relativePath)
            guard hasModelFiles(at: legacyDir) else { continue }
            try? FileManager.default.createDirectory(at: newDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: newDir.path) {
                try? FileManager.default.removeItem(at: newDir)
            }
            try? FileManager.default.copyItem(at: legacyDir, to: newDir)
            return
        }
    }

    private static func hasModelFiles(at url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return false }
        return contents.contains { $0.hasSuffix(".bin") }
    }
}
