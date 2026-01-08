//
//  ScheduleView.swift
//  Luna
//
//  Created by Soupy-dev
//

import SwiftUI
import Combine
import Kingfisher

struct ScheduleView: View {
    @AppStorage("showLocalScheduleTime") private var showLocalScheduleTime = true
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var scheduleEntries: [AniListAiringScheduleEntry] = []
    @State private var dayBuckets: [DayBucket] = []
    @State private var currentDayAnchor = Date()
    
    @StateObject private var accentColorManager = AccentColorManager.shared
    
    private let scheduleDaysAhead = 7
    private let dayChangeTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()
    
    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                scheduleContent
            }
        } else {
            NavigationView {
                scheduleContent
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }
    
    private var scheduleContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isLoading {
                loadingView
            } else if let errorMessage = errorMessage {
                errorView(errorMessage)
            } else if dayBuckets.isEmpty {
                emptyStateView
            } else {
                mainScheduleView
            }
        }
        .navigationTitle("Schedule")
        .task {
            await loadSchedule()
        }
        .refreshable {
            await loadSchedule()
        }
        .onReceive(dayChangeTimer) { _ in
            Task { await handleDayChangeIfNeeded() }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading schedule...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            Button("Retry") {
                Task { await loadSchedule() }
            }
            .buttonStyle(.bordered)
            .tint(accentColorManager.currentAccentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("No Upcoming Episodes")
                .font(.title2)
                .fontWeight(.bold)
            Text("No episodes scheduled in the next week.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var mainScheduleView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Time zone toggle section
                timeZoneToggleSection
                
                // Schedule days
                ForEach(dayBuckets) { bucket in
                    daySection(bucket: bucket)
                }
            }
            .padding(.top)
            .padding(.bottom, 100)
        }
    }
    
    private var timeZoneToggleSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timezone")
                    .font(.headline)
                Text("Times are shown in \(showLocalScheduleTime ? "your local time" : "UTC")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("Local time", isOn: $showLocalScheduleTime)
                .labelsHidden()
                .tint(accentColorManager.currentAccentColor)
                .onChange(of: showLocalScheduleTime) { _ in
                    regroupBuckets()
                }
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func daySection(bucket: DayBucket) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Day header
            Text(formattedDay(bucket.date))
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            if bucket.items.isEmpty {
                Text("No episodes scheduled")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    ForEach(bucket.items) { item in
                        scheduleItemCard(item: item)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func scheduleItemCard(item: AniListAiringScheduleEntry) -> some View {
        HStack(spacing: 12) {
            // Cover image
            if let coverURL = item.coverImage, let url = URL(string: coverURL) {
                KFImage(url)
                    .resizable()
                    .placeholder {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 85)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 85)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Label("Ep. \(item.episode)", systemImage: "film")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Label(formattedTime(item.airingAt), systemImage: "clock")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
    }
    
    // MARK: - Data Loading
    
    private func loadSchedule() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let entries = try await AniListService.shared.fetchAiringSchedule(daysAhead: scheduleDaysAhead)
            await MainActor.run {
                isLoading = false
                scheduleEntries = entries
                currentDayAnchor = Date()
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
        let startOfToday = calendar.startOfDay(for: Date())
        
        var buckets: [DayBucket] = []
        for offset in 0...scheduleDaysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else {
                continue
            }
            
            let dayItems = entries
                .filter { entry in
                    entry.airingAt >= calendar.startOfDay(for: day) && entry.airingAt < nextDay
                }
                .sorted { $0.airingAt < $1.airingAt }
            
            buckets.append(DayBucket(date: calendar.startOfDay(for: day), items: dayItems))
        }
        
        dayBuckets = buckets
    }
    
    private func regroupBuckets() {
        updateBuckets(with: scheduleEntries)
    }
    
    private func handleDayChangeIfNeeded() async {
        let calendar = makeCalendar()
        let trackedDay = calendar.startOfDay(for: currentDayAnchor)
        let today = calendar.startOfDay(for: Date())
        
        if today != trackedDay {
            await loadSchedule()
        } else {
            await MainActor.run {
                currentDayAnchor = Date()
                updateBuckets(with: scheduleEntries)
            }
        }
    }
    
    private func makeCalendar() -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = showLocalScheduleTime ? .current : TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    
    private func formattedDay(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let compareDate = calendar.startOfDay(for: date)
        
        if compareDate == today {
            return "Today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), compareDate == tomorrow {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            formatter.timeZone = showLocalScheduleTime ? .current : TimeZone(secondsFromGMT: 0)
            return formatter.string(from: date)
        }
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
