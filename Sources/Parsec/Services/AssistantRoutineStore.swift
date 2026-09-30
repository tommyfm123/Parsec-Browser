import AppKit
import Foundation
import Observation

enum RoutineSchedule: String, Codable, CaseIterable, Identifiable {
    case manual
    case hourly
    case daily
    case weekdays
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: "Manual"
        case .hourly: "Cada hora"
        case .daily: "Diaria"
        case .weekdays: "Días hábiles"
        case .weekly: "Semanal"
        }
    }

    var usesTime: Bool { self != .manual && self != .hourly }
}

struct AssistantRoutine: Codable, Identifiable {
    static let weekdayNames = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
    private static let workingWeekdays = 2...6
    private static let defaultHour = 9
    private static let defaultWeekday = 2

    let id: UUID
    let profileID: UUID
    var title: String
    var summary: String
    var prompt: String
    var usesAgent: Bool
    var spaceID: UUID?
    var schedule: RoutineSchedule
    var hour: Int
    var minute: Int
    var weekday: Int
    let createdAt: Date
    var lastRunAt: Date?

    init(profileID: UUID, title: String = "", summary: String = "", prompt: String = "", usesAgent: Bool = false, schedule: RoutineSchedule = .manual, hour: Int = defaultHour, minute: Int = 0) {
        id = UUID()
        self.profileID = profileID
        self.title = title
        self.summary = summary
        self.prompt = prompt
        self.usesAgent = usesAgent
        self.schedule = schedule
        self.hour = hour
        self.minute = minute
        weekday = Self.defaultWeekday
        createdAt = Date()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        profileID = try container.decode(UUID.self, forKey: .profileID)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        prompt = try container.decode(String.self, forKey: .prompt)
        usesAgent = try container.decodeIfPresent(Bool.self, forKey: .usesAgent) ?? false
        spaceID = try container.decodeIfPresent(UUID.self, forKey: .spaceID)
        schedule = try container.decodeIfPresent(RoutineSchedule.self, forKey: .schedule) ?? .manual
        hour = try container.decodeIfPresent(Int.self, forKey: .hour) ?? Self.defaultHour
        minute = try container.decodeIfPresent(Int.self, forKey: .minute) ?? 0
        weekday = try container.decodeIfPresent(Int.self, forKey: .weekday) ?? Self.defaultWeekday
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastRunAt = try container.decodeIfPresent(Date.self, forKey: .lastRunAt)
    }

    var symbolName: String {
        usesAgent ? "cursorarrow.motionlines" : "sparkles"
    }

    var scheduleDescription: String {
        let time = String(format: "%02d:%02d", hour, minute)
        return switch schedule {
        case .manual: "Manual"
        case .hourly: String(format: "Cada hora, al minuto %02d", minute)
        case .daily: "Todos los días a las \(time)"
        case .weekdays: "Días hábiles a las \(time)"
        case .weekly: "Todos los \(Self.weekdayNames[weekday - 1]) a las \(time)"
        }
    }

    func nextRun(after date: Date) -> Date? {
        matchingComponents
            .compactMap { Calendar.current.nextDate(after: date, matching: $0, matchingPolicy: .nextTime) }
            .min()
    }

    private var matchingComponents: [DateComponents] {
        switch schedule {
        case .manual: []
        case .hourly: [DateComponents(minute: minute)]
        case .daily: [DateComponents(hour: hour, minute: minute)]
        case .weekdays: Self.workingWeekdays.map { DateComponents(hour: hour, minute: minute, weekday: $0) }
        case .weekly: [DateComponents(hour: hour, minute: minute, weekday: weekday)]
        }
    }
}

@MainActor
@Observable
final class AssistantRoutineStore {
    static let shared = AssistantRoutineStore()
    private static let fileName = "assistant-routines.json"
    private static let checkInterval: TimeInterval = 30
    private static let catchUpLimit: TimeInterval = 60 * 60

    private(set) var routines: [AssistantRoutine]
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var scheduler: Timer?

    init() {
        fileURL = StorageConstants.applicationSupportURL.appending(path: Self.fileName)
        routines = Self.load(from: fileURL)
    }

    func list(profileID: UUID) -> [AssistantRoutine] {
        routines.filter { $0.profileID == profileID }.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ routine: AssistantRoutine) {
        if let index = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[index] = routine
        } else {
            routines.insert(routine, at: 0)
        }
        persist()
    }

    func delete(_ id: UUID) {
        routines.removeAll { $0.id == id }
        persist()
    }

    func startScheduler() {
        guard scheduler == nil else { return }
        scheduler = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { _ in
            Task { @MainActor in AssistantRoutineStore.shared.runDueRoutines() }
        }
    }

    private func runDueRoutines() {
        guard let model = AppDelegate.shared.mainModel else { return }
        let now = Date()
        let dueRoutines = routines.compactMap { routine -> (routine: AssistantRoutine, dueDate: Date)? in
            guard routine.profileID == model.profileID,
                  let dueDate = routine.nextRun(after: routine.lastRunAt ?? routine.createdAt),
                  dueDate <= now else { return nil }
            return (routine, dueDate)
        }
        guard !dueRoutines.isEmpty else { return }
        for (routine, dueDate) in dueRoutines {
            markRun(routine.id, at: now)
            if now.timeIntervalSince(dueDate) <= Self.catchUpLimit { model.run(routine) }
        }
        persist()
    }

    private func markRun(_ id: UUID, at date: Date) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[index].lastRunAt = date
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(routines)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSApp.presentError(error)
        }
    }

    private static func load(from fileURL: URL) -> [AssistantRoutine] {
        guard let data = try? Data(contentsOf: fileURL), let routines = try? JSONDecoder().decode([AssistantRoutine].self, from: data) else { return [] }
        return routines
    }
}
