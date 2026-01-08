//
//  ScheduleViewModel.swift
//  Luna
//
//  Created by Soupy-dev
//

import Foundation
import Combine

final class ScheduleViewModel: ObservableObject {
    static let shared = ScheduleViewModel()
    
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var scheduleEntries: [AniListAiringScheduleEntry] = []
    @Published var dayBuckets: [DayBucket] = []
    @Published var currentDayAnchor = Date()
    
    private var cancellables = Set<AnyCancellable>()
    private let scheduleDaysAhead = 7
    
    private init() {}
    
    func loadSchedule() async {
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
    
    func updateBuckets(with entries: [AniListAiringScheduleEntry]) {
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
    
    func regroupBuckets() {
        updateBuckets(with: scheduleEntries)
    }
    
    func handleDayChangeIfNeeded() async {
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
        calendar.timeZone = .current
        return calendar
    }
}

struct DayBucket: Identifiable {
    let id = UUID()
    let date: Date
    let items: [AniListAiringScheduleEntry]
}
