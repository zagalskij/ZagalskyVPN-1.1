import Foundation
import SwiftUI

@MainActor
struct PersonalizationEditor: View {
    @ObservedObject private var store: PersonalizationStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool

    @State private var name: String
    @State private var birthday: Birthday?
    @State private var dateChoice: Date
    @State private var choosingDate = false
    @State private var errorMessage: String?

    private let isRequired: Bool
    private let russianLocale = Locale(identifier: "ru_RU")

    init(store: PersonalizationStore, isRequired: Bool) {
        self.store = store
        self.isRequired = isRequired
        _name = State(initialValue: store.profile?.name ?? "")
        _birthday = State(initialValue: store.profile?.birthday)
        _dateChoice = State(initialValue: store.profile?.birthday.pickerDate ?? Birthday.latestPickerDate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                fields

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(VPNTheme.warning)
                }

                Button(action: save) {
                    Text(isRequired ? "Продолжить" : "Сохранить")
                        .font(.headline)
                        .foregroundStyle(VPNTheme.background)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .padding(.horizontal, 16)
                        .background(VPNTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                if !isRequired {
                    Button("Отмена") { dismiss() }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 420)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            ZStack {
                VPNTheme.background
                RadialGradient(
                    colors: [VPNTheme.accent.opacity(0.18), .clear],
                    center: .top,
                    startRadius: 10,
                    endRadius: 340
                )
            }
            .ignoresSafeArea()
        }
        .tint(VPNTheme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $choosingDate) {
            datePicker
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZagMark()
                .stroke(VPNTheme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: 34, height: 38)
                .padding(12)
                .background(VPNTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)

            Text(isRequired ? "Давай познакомимся" : "Личный профиль")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            Text("Имя и дата рождения хранятся на этом iPhone и нужны для приветствий и поздравлений.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Имя").font(.subheadline.weight(.semibold))
                TextField("Как к тебе обращаться?", text: $name)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { isNameFocused = false }
                    .accessibilityLabel("Имя")
                    .padding(14)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Дата рождения").font(.subheadline.weight(.semibold))
                Button {
                    isNameFocused = false
                    dateChoice = birthday?.pickerDate ?? Birthday.latestPickerDate
                    choosingDate = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar").foregroundStyle(VPNTheme.accent)
                        Text(formattedBirthday)
                            .foregroundStyle(birthday == nil ? Color.secondary : Color.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Дата рождения")
                .accessibilityValue(formattedBirthday)
            }
        }
    }

    private var datePicker: some View {
        NavigationStack {
            DatePicker(
                "Дата рождения",
                selection: $dateChoice,
                in: ...Birthday.latestPickerDate,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VPNTheme.background)
            .navigationTitle("Дата рождения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { choosingDate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Выбрать") {
                        birthday = Birthday(dateChoice, calendar: Birthday.pickerCalendar)
                        errorMessage = nil
                        choosingDate = false
                    }
                }
            }
        }
        .environment(\.calendar, Birthday.pickerCalendar)
        .environment(\.timeZone, Birthday.pickerCalendar.timeZone)
        .environment(\.locale, russianLocale)
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var formattedBirthday: String {
        guard let date = birthday?.pickerDate else { return "Выбрать дату" }
        let formatter = DateFormatter()
        formatter.locale = russianLocale
        formatter.calendar = Birthday.pickerCalendar
        formatter.timeZone = Birthday.pickerCalendar.timeZone
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private func save() {
        isNameFocused = false
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Введите имя."
            isNameFocused = true
            return
        }
        guard let birthday else {
            errorMessage = "Выберите дату рождения."
            return
        }

        do {
            try store.save(name: name, birthday: birthday)
            if !isRequired { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
