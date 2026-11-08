import Foundation
import SwiftUI

/// A short note typed straight into the notch, with an optional color tag.
/// Pure value + list operations (tested); `QuickNotesManager` persists.
struct QuickNote: Codable, Equatable, Identifiable {
    enum Tag: String, Codable, CaseIterable { case none, red, amber, green, blue }

    var id = UUID()
    var text: String
    var tag: Tag = .none
    var done = false
    var created = Date()

    /// Adds a trimmed note at the top; blank text is ignored.
    static func adding(_ text: String, tag: Tag, to list: [QuickNote], now: Date = Date()) -> [QuickNote] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return list }
        return [QuickNote(text: t, tag: tag, created: now)] + list
    }

    /// Open notes first (newest first), done notes after — each group keeps its order.
    static func sorted(_ list: [QuickNote]) -> [QuickNote] {
        list.filter { !$0.done } + list.filter(\.done)
    }
}

extension QuickNote.Tag {
    var color: Color? {
        switch self {
        case .none: nil
        case .red: Theme.Palette.danger
        case .amber: Theme.Palette.warning
        case .green: Theme.Palette.success
        case .blue: Theme.Palette.accent
        }
    }

    var name: String { self == .none ? "No tag" : rawValue.capitalized }
}

/// Quick notes, saved locally (UserDefaults JSON). The longer free-form
/// scratchpad is still NotesController (⌥⌘N).
final class QuickNotesManager: ObservableObject {
    static let shared = QuickNotesManager()

    @Published private(set) var notes: [QuickNote] = []

    private let key = "quickNotes"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([QuickNote].self, from: data) {
            notes = saved
        }
    }

    func add(_ text: String, tag: QuickNote.Tag) { save(QuickNote.adding(text, tag: tag, to: notes)) }

    func toggleDone(_ note: QuickNote) {
        save(notes.map { $0.id == note.id ? { var n = $0; n.done.toggle(); return n }($0) : $0 })
    }

    func setTag(_ tag: QuickNote.Tag, for note: QuickNote) {
        save(notes.map { $0.id == note.id ? { var n = $0; n.tag = tag; return n }($0) : $0 })
    }

    func update(_ note: QuickNote, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return delete(note) }
        save(notes.map { $0.id == note.id ? { var n = $0; n.text = t; return n }($0) : $0 })
    }

    func delete(_ note: QuickNote) { save(notes.filter { $0.id != note.id }) }

    func clearDone() { save(notes.filter { !$0.done }) }

    private func save(_ list: [QuickNote]) {
        notes = list
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Notes widget: an input with tag dots, then the notes. Click a note's
/// circle to tick it off; right-click to edit, retag or delete.
struct QuickNotesView: View {
    @ObservedObject var store = QuickNotesManager.shared
    /// Fewer rows in the compact glance column.
    var maxRows = 6

    @State private var draft = ""
    @State private var tag: QuickNote.Tag = .none
    @State private var editing: QuickNote.ID?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField(editing == nil ? "What's on your mind?" : "Edit note", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.Typo.body)
                    .foregroundColor(Theme.Palette.text)
                    .focused($focused)
                    .onSubmit(commit)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.control).fill(Theme.Palette.elevated))
                ForEach(QuickNote.Tag.allCases.filter { $0 != .none }, id: \.self) { t in
                    Button { tag = tag == t ? .none : t } label: {
                        Circle().fill(t.color ?? .clear)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(Theme.Palette.text, lineWidth: tag == t ? 2 : 0)
                                .frame(width: 14, height: 14))
                            .frame(width: 18, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Tag \(t.name.lowercased())")
                    .accessibilityLabel("\(t.name) tag")
                    .accessibilityAddTraits(tag == t ? .isSelected : [])
                }
            }
            if store.notes.isEmpty {
                Text("Jot it down — press Return to save.")
                    .font(Theme.Typo.label).foregroundColor(Theme.Palette.textSecondary)
            }
            ForEach(QuickNote.sorted(store.notes).prefix(maxRows)) { note in
                row(note)
            }
            if store.notes.count > maxRows {
                Text("+\(store.notes.count - maxRows) more")
                    .font(Theme.Typo.caption).foregroundColor(Theme.Palette.textTertiary)
            }
        }
    }

    private func row(_ note: QuickNote) -> some View {
        HStack(spacing: 6) {
            Button { store.toggleDone(note) } label: {
                Image(systemName: note.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(note.done ? Theme.Palette.success : Theme.Palette.textSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(note.done ? "Mark not done" : "Mark done")
            if let c = note.tag.color {
                Capsule().fill(c).frame(width: 3, height: 14).accessibilityHidden(true)
            }
            Text(note.text)
                .font(Theme.Typo.body)
                .strikethrough(note.done)
                .foregroundColor(note.done ? Theme.Palette.textSecondary : Theme.Palette.text)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            // Short and static ("18m ago") — a live seconds counter is noise.
            Text(note.created.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                .font(Theme.Typo.caption).foregroundColor(Theme.Palette.textTertiary)
                .lineLimit(1).fixedSize()
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit") { editing = note.id; draft = note.text; tag = note.tag; focused = true }
            Menu("Tag") {
                ForEach(QuickNote.Tag.allCases, id: \.self) { t in
                    Button(t.name) { store.setTag(t, for: note) }
                }
            }
            Button(note.done ? "Mark Not Done" : "Mark Done") { store.toggleDone(note) }
            Divider()
            Button("Delete", role: .destructive) { store.delete(note) }
            if store.notes.contains(where: \.done) {
                Button("Clear Done Notes") { store.clearDone() }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.tag == .none ? "" : "\(note.tag.name), ")\(note.text)\(note.done ? ", done" : "")")
    }

    private func commit() {
        if let id = editing, let note = store.notes.first(where: { $0.id == id }) {
            store.update(note, text: draft)
            store.setTag(tag, for: note)
        } else {
            store.add(draft, tag: tag)
        }
        draft = ""
        tag = .none
        editing = nil
    }
}
