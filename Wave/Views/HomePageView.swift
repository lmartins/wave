import SwiftUI
import AppKit
import Combine

struct HomePageView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    StatCard(
                        value: formatWordCount(appState.historyManager.wordsToday),
                        label: "Today · words"
                    )
                    StatCard(
                        value: formatWordCount(appState.historyManager.wordsThisWeek),
                        label: "This week · words"
                    )
                    StatCard(
                        value: formatDuration(appState.historyManager.estimatedTimeSavedSeconds),
                        label: "Time saved · est."
                    )
                }

                if appState.historyManager.totalWords > 0 {
                    section("Activity") {
                        ActivityHeatmapView(
                            grid: appState.historyManager.activityHeatmap,
                            maxValue: appState.historyManager.activityHeatmapMax
                        )
                        Text("Darker cells mean more words dictated at that day and hour.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    section("This Week") {
                        WeekBarChartView(
                            counts: appState.historyManager.wordsLast7Days,
                            labels: appState.historyManager.wordsLast7DayLabels,
                            maxValue: appState.historyManager.wordsLast7DaysMax
                        )
                    }
                }

                if appState.historyManager.records.isEmpty {
                    emptyState
                } else {
                    section("Recent") {
                        LazyVStack(spacing: 0) {
                            ForEach(appState.historyManager.records.prefix(5)) { record in
                                TranscriptionRow(record: record) {
                                    appState.historyManager.remove(record.id)
                                }
                            }
                        }
                        Text("Right-click for more options")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
            Text("No transcriptions yet")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text("Your activity chart and time-saved estimate will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Activity Heatmap

private struct ActivityHeatmapView: View {
    let grid: [[Int]]
    let maxValue: Int

    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]
    private let hourMarkers = [0, 6, 12, 18]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(" ")
                    .font(.system(size: 9, design: .monospaced))
                    .frame(width: 12)
                ForEach(hourMarkers, id: \.self) { hour in
                    Text(hourLabel(hour))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ForEach(0..<7, id: \.self) { day in
                HStack(spacing: 2) {
                    Text(weekdays[day])
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, alignment: .leading)

                    HStack(spacing: 2) {
                        ForEach(0..<24, id: \.self) { hour in
                            let value = grid[day][hour]
                            RoundedRectangle(cornerRadius: 2)
                                .fill(cellColor(value))
                                .frame(maxWidth: .infinity)
                                .frame(height: 10)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func cellColor(_ value: Int) -> Color {
        guard value > 0, maxValue > 0 else {
            return Color.primary.opacity(0.06)
        }
        let intensity = sqrt(Double(value) / Double(maxValue))
        return Color.brand.opacity(0.15 + intensity * 0.85)
    }

    private func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12a"
        case 6: return "6a"
        case 12: return "12p"
        case 18: return "6p"
        default: return ""
        }
    }
}

// MARK: - Week Bar Chart

private struct WeekBarChartView: View {
    let counts: [Int]
    let labels: [String]
    let maxValue: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(counts.indices, id: \.self) { index in
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 72)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.brand.opacity(counts[index] > 0 ? 0.85 : 0.15))
                            .frame(height: barHeight(counts[index]))
                    }
                    Text(labels[index])
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func barHeight(_ count: Int) -> CGFloat {
        guard count > 0 else { return 4 }
        let peak = Swift.max(maxValue, 1)
        return Swift.max(8, CGFloat(count) / CGFloat(peak) * 72)
    }
}

// MARK: - Transcription Row

private struct TranscriptionRow: View {
    let record: TranscriptionRecord
    let onDelete: () -> Void
    @State private var timeLabel: String = ""
    private let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.text)
                    .font(.system(size: 12))
                    .lineLimit(2)
                Text(timeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .onAppear { timeLabel = relativeTime(record.date) }
                    .onReceive(timer) { _ in timeLabel = relativeTime(record.date) }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.text, forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Formatting

private func formatWordCount(_ count: Int) -> String {
    if count >= 1000 {
        return String(format: "%.1fk", Double(count) / 1000)
    }
    return "\(count)"
}

private func formatDuration(_ seconds: Int) -> String {
    guard seconds > 0 else { return "0m" }
    if seconds < 3600 {
        let minutes = max(1, seconds / 60)
        return "\(minutes)m"
    }
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    if minutes == 0 { return "\(hours)h" }
    return "\(hours)h \(minutes)m"
}

private func relativeTime(_ date: Date) -> String {
    let seconds = Int(-date.timeIntervalSinceNow)
    if seconds < 60 { return "just now" }
    if seconds < 3600 { return "\(seconds / 60)m ago" }
    if seconds < 86400 { return "\(seconds / 3600)h ago" }
    return "\(seconds / 86400)d ago"
}