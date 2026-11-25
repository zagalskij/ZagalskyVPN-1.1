import Combine
import Foundation

struct PersonalizationProfile: Codable {
    let name: String
    let birthday: Birthday
}

struct Birthday: Codable {
    let year: Int
    let month: Int
    let day: Int

    static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    static let pickerCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    static var latestPickerDate: Date {
        Birthday(.now, calendar: localCalendar).pickerDate ?? .now
    }

    init(_ date: Date, calendar: Calendar) {
        year = calendar.component(.year, from: date)
        month = calendar.component(.month, from: date)
        day = calendar.component(.day, from: date)
    }

    var pickerDate: Date? {
        Self.pickerCalendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    func matchesMonthAndDay(of date: Date, calendar: Calendar) -> Bool {
        month == calendar.component(.month, from: date)
            && day == calendar.component(.day, from: date)
    }
}

@MainActor
final class PersonalizationStore: ObservableObject {
    @Published private(set) var profile: PersonalizationProfile?

    private struct StoredState: Codable {
        let profile: PersonalizationProfile
        let complimentIndex: Int
        let birthdayIndex: Int
    }

    private static let compliments = [
        "у тебя отличный вкус!",
        "твой взгляд на мир вдохновляет.",
        "у тебя здорово получается находить свой путь.",
        "ты умеешь замечать хорошее в мелочах.",
        "твоя любознательность восхищает.",
        "с тобой даже обычный день становится ярче.",
        "твои идеи заслуживают внимания!",
        "ты умеешь смотреть на вещи по-своему."
    ]

    private static let birthdayGreetings = [
        "с днём рождения! Пусть сегодня сбудется одно из твоих желаний.",
        "с днём рождения! Желаю тебе радостных встреч и приятных сюрпризов.",
        "с днём рождения! Пусть новый год твоей жизни будет полон хороших историй."
    ]

    private var complimentIndex = 0
    private var birthdayIndex = 0

    init() {
        guard let url = try? Self.storageURL(createDirectory: false),
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(StoredState.self, from: data) else {
            return
        }

        complimentIndex = Self.nextIndex(after: stored.complimentIndex, count: Self.compliments.count)
        birthdayIndex = Self.nextIndex(after: stored.birthdayIndex, count: Self.birthdayGreetings.count)
        profile = stored.profile
        try? persist(stored.profile)
    }

    var greeting: String? {
        guard let profile else { return nil }
        let birthday = profile.birthday.matchesMonthAndDay(of: .now, calendar: Birthday.localCalendar)
        let message = birthday
            ? Self.birthdayGreetings[birthdayIndex]
            : Self.compliments[complimentIndex]
        return "\(profile.name), \(message)"
    }

    func save(name: String, birthday: Birthday) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw PersonalizationError.emptyName }

        guard let date = birthday.pickerDate, date <= Birthday.latestPickerDate else {
            throw PersonalizationError.futureDate
        }

        let newProfile = PersonalizationProfile(name: cleanName, birthday: birthday)
        do {
            try persist(newProfile)
        } catch {
            throw PersonalizationError.storageUnavailable
        }
        profile = newProfile
    }

    private func persist(_ profile: PersonalizationProfile) throws {
        let state = StoredState(profile: profile, complimentIndex: complimentIndex, birthdayIndex: birthdayIndex)
        let data = try JSONEncoder().encode(state)
        let url = try Self.storageURL(createDirectory: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static func nextIndex(after index: Int, count: Int) -> Int {
        (0..<count).contains(index) ? (index + 1) % count : 0
    }

    private static func storageURL(createDirectory: Bool) throws -> URL {
        let files = FileManager.default
        let support = try files.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createDirectory
        )
        var directory = support.appendingPathComponent("Personalization", isDirectory: true)
        if createDirectory {
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            var attributes = URLResourceValues()
            attributes.isExcludedFromBackup = true
            try directory.setResourceValues(attributes)
        }
        return directory.appendingPathComponent("profile.json")
    }
}

private enum PersonalizationError: LocalizedError {
    case emptyName
    case futureDate
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Введите имя."
        case .futureDate: return "Дата рождения не может быть в будущем."
        case .storageUnavailable: return "Не удалось сохранить профиль на iPhone. Попробуйте ещё раз."
        }
    }
}
