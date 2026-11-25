import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ProfileEditor: View {
    struct Input: Identifiable {
        let id = UUID()
        let name: String
        let configuration: String
    }

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var configuration: String
    @State private var errorMessage: String?
    @State private var showFileImporter = false
    @State private var isSaving = false

    private let isEditing: Bool
    private let save: @MainActor (String, String) async throws -> Void

    init(input: Input, save: @escaping @MainActor (String, String) async throws -> Void) {
        _name = State(initialValue: input.name)
        _configuration = State(initialValue: input.configuration)
        isEditing = !input.configuration.isEmpty
        self.save = save
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Название")
                            .font(.subheadline.weight(.semibold))
                        TextField("Мой сервер", text: $name)
                            .accessibilityLabel("Название конфигурации")
                            .padding(12)
                            .background(VPNTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Конфигурация AmneziaWG")
                            .font(.subheadline.weight(.semibold))
                        ViewThatFits {
                            HStack(spacing: 12) {
                                pasteButton
                                fileButton
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                pasteButton
                                fileButton
                            }
                        }
                        TextEditor(text: $configuration)
                            .font(.system(.callout, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .frame(minHeight: 240)
                            .background(VPNTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(VPNTheme.border)
                                    .allowsHitTesting(false)
                            }
                            .accessibilityLabel("Текст конфигурации")
                        if configuration.isEmpty {
                            Text("Используйте профиль AmneziaWG с разделами [Interface] и [Peer].")
                                .font(.footnote)
                                .foregroundStyle(VPNTheme.muted)
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(VPNTheme.warning)
                            .accessibilityElement(children: .combine)
                    }
                }
                .padding(20)
                .disabled(isSaving)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(VPNTheme.background.ignoresSafeArea())
            .navigationTitle(isEditing ? "Изменить конфигурацию" : "Новая конфигурация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(VPNTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .accessibilityLabel("Сохраняем конфигурацию")
                    } else {
                        Button("Сохранить", action: saveConfiguration)
                            .fontWeight(.semibold)
                            .disabled(configuration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.data]) { result in
                importConfiguration(result)
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var pasteButton: some View {
        PasteButton(payloadType: String.self) { values in
            guard let value = values.first else { return }
            configuration = value
            errorMessage = nil
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.roundedRectangle)
        .tint(VPNTheme.accent)
        .foregroundStyle(VPNTheme.background)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: 44)
    }

    private var fileButton: some View {
        Button {
            showFileImporter = true
        } label: {
            Label("Открыть файл", systemImage: "doc")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(VPNTheme.accent)
    }

    private func saveConfiguration() {
        isSaving = true
        errorMessage = nil
        let profileName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { isSaving = false }
            do {
                try await save(profileName, configuration)
                dismiss()
            } catch {
                errorMessage = TunnelIssue.message(for: error)
            }
        }
    }

    private func importConfiguration(_ result: Result<URL, Error>) {
        errorMessage = nil
        do {
            let url = try result.get()
            guard ["conf", "txt", "wg"].contains(url.pathExtension.lowercased()) else {
                errorMessage = "Выберите файл конфигурации с расширением .conf, .txt или .wg."
                return
            }
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            let limit = TunnelSettings.maximumConfigurationSize
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: limit + 1) ?? Data()
            guard data.count <= limit else {
                errorMessage = "Файл слишком большой. Максимальный размер — 256 КБ."
                return
            }
            guard let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "Файл должен содержать текст конфигурации в кодировке UTF-8."
                return
            }

            configuration = text
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = url.deletingPathExtension().lastPathComponent
            }
        } catch {
            errorMessage = "Не удалось прочитать файл. Проверьте, доступен ли он в приложении «Файлы»."
        }
    }
}
