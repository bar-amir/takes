import AppKit
import SwiftUI

/// Settings › History: past runs grouped by day (click one to see its takes), whether to keep them, and the run log.
struct HistoryTab: View {
    @ObservedObject var store = Store.shared
    @State private var search = ""
    @State private var expanded: Set<String> = []

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    var body: some View {
        SettingsPage {
            if !store.history.isEmpty {
                StyledTextField(placeholder: String(localized: "Search drafts and takes"), text: $search, height: 30)
                    .accessibilityLabel("Search history")
            }
            if store.history.isEmpty {
                FormSection(String(localized: "Runs")) {
                    Text(store.settings.keepHistory ? "No runs yet. Takes you write show up here for 30 days." : "History is off.")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                        .formRowPadding()
                }
            } else if days.isEmpty {
                FormSection(String(localized: "Runs")) {
                    Text("Nothing matches “\(search)”.").font(.system(size: 13)).foregroundStyle(Theme.secondaryText).formRowPadding()
                }
            } else {
                ForEach(days, id: \.title) { day in
                    FormSection(day.title) {
                        ForEach(day.entries) { entry in
                            entryRow(entry)
                            if entry.id != day.entries.last?.id { FormDivider(inset: 34) }
                        }
                    }
                }
            }

            FormSection(String(localized: "Keeping history")) {
                FormToggle(String(localized: "Keep 30 days of history, on this Mac only"), isOn: $store.settings.keepHistory)
                FormDivider()
                FormRow(String(localized: "Run log"), detail: String(localized: "Timings for bug reports. It never contains your text.")) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([RunLog.url]) }
                        .buttonStyle(SecondaryButtonStyle(height: 28))
                        .fixedSize()
                }
                FormDivider()
                FormRow(String(localized: "Delete all history")) {
                    Button("Clear History…", action: clear)
                        .buttonStyle(DestructiveButtonStyle())
                        .disabled(store.history.isEmpty)
                }
            }
        }
    }

    private var days: [(title: String, entries: [HistoryEntry])] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let entries = query.isEmpty ? store.history : store.history.filter { entry in
            entry.draft.localizedCaseInsensitiveContains(query) || entry.takes.contains { $0.localizedCaseInsensitiveContains(query) }
                || entry.appName.localizedCaseInsensitiveContains(query) || entry.presetName.localizedCaseInsensitiveContains(query)
        }
        var result: [(title: String, entries: [HistoryEntry])] = []
        for entry in entries {
            // "aujourd’hui", "tänään": a section header starts with a capital in every language.
            let day = Self.dayFormat.string(from: entry.date)
            let title = day.prefix(1).uppercased(with: .current) + day.dropFirst()
            if result.last?.title == title { result[result.count - 1].entries.append(entry) } else { result.append((title, [entry])) }
        }
        return result
    }

    private func entryRow(_ entry: HistoryEntry) -> some View {
        let open = expanded.contains(entry.id)
        let color = store.presets.first { $0.name == entry.presetName }?.colorHex
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Motion.animation()) {
                    if open { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 10)
                    Circle().fill(color.map { Color(hex: $0) } ?? Theme.tertiaryText).frame(width: 8, height: 8)
                    Text(entry.draft.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 12)
                    Text("\(entry.presetName) · \(entry.appName) · \(Self.timeFormat.string(from: entry.date))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .fixedSize()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(entry.presetName) in \(entry.appName): \(entry.draft)")
            .accessibilityValue(open ? "Expanded" : "Collapsed")

            if open {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(entry.takes.enumerated()), id: \.offset) { index, take in
                        HStack(alignment: .top, spacing: 12) {
                            Text(entry.pastedIndex == index ? String(localized: "PASTED") : String(localized: "TAKE \(index + 1)"))
                                .font(.mono(10, bold: true))
                                .foregroundStyle(entry.pastedIndex == index ? Theme.accent : Theme.secondaryText)
                                .frame(width: 56, alignment: .leading)
                                .padding(.top, 2)
                            Text(take).font(.system(size: 13)).lineSpacing(2).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(take, forType: .string)
                            } label: { Image(systemName: "doc.on.doc").font(.system(size: 11, weight: .medium)) }
                            .buttonStyle(SecondaryButtonStyle(height: 24))
                            .help("Copy take")
                            .accessibilityLabel("Copy take \(index + 1)")
                        }
                    }
                }
                .padding(.leading, 38)
                .transition(.opacity)
            }
        }
        .formRowPadding()
    }

    private func clear() {
        guard confirmDestructive(String(localized: "Clear all history?"),
                                 message: String(localized: "This deletes every draft and take Takes has kept on this Mac. You can't undo this."),
                                 button: String(localized: "Clear History")) else { return }
        store.history = []
        expanded = []
    }
}
