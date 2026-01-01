import SwiftUI

struct ScheduleView: View {
    @AppStorage("showLocalScheduleTime") private var showLocalScheduleTime = true
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var dayBuckets: [DayBucket] = []

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading schedule…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await loadSchedule() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if dayBuckets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No upcoming episodes in the next week.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        HStack {
                            Text("Times are shown in \(showLocalScheduleTime ? "your local time" : "UTC").")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle("Local time", isOn: $showLocalScheduleTime)
                                .labelsHidden()
                                .onChange(of: showLocalScheduleTime) { _ in
                                    regroupBuckets()
                                }
                        }
                    }

                    ForEach(dayBuckets) { bucket in
                        Section(header: Text(formattedDay(bucket.date))) {
                            ForEach(bucket.items) { item in
                                HStack(spacing: 12) {
                                    if let cover = item.coverImage, let url = URL(string: cover) {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Color.gray.opacity(0.2)
                                        }
                                        .frame(width: 60, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.headline)
                                        Text("Episode \(item.episode)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Text(formattedTime(item.airingAt))
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                #if !os(tvOS)
                .navigationTitle("Schedule")
                #endif
            }
        }
        .task {
            await loadSchedule()
        }
    }

    private func loadSchedule() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let entries = try await AniListService.shared.fetchAiringSchedule(daysAhead: 7)
            await MainActor.run {
                isLoading = false
                updateBuckets(with: entries)
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateBuckets(with entries: [AniListAiringScheduleEntry]) {
        let calendar = makeCalendar()
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.airingAt)
        }

        let buckets = grouped.map { key, value in
            DayBucket(date: key, items: value.sorted { $0.airingAt < $1.airingAt })
        }
        dayBuckets = buckets.sorted { $0.date < $1.date }
    }

    private func regroupBuckets() {
        let flat = dayBuckets.flatMap { $0.items }
        updateBuckets(with: flat)
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = showLocalScheduleTime ? .current : TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func formattedDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        formatter.timeZone = showLocalScheduleTime ? .current : TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.timeZone = showLocalScheduleTime ? .current : TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

private struct DayBucket: Identifiable {
    let id = UUID()
    let date: Date
    let items: [AniListAiringScheduleEntry]
}
*** End File