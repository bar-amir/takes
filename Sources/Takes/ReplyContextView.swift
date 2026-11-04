import AppKit
import SwiftUI

/// The context row above the draft: nothing, a compact chip, or the expanded box to type or paste into.
struct ReplyContextBar: View {
    @ObservedObject var model: PanelModel

    static let chipHeight: CGFloat = Spacing.control
    static let editorHeight: CGFloat = 88

    /// How much taller compose gets, so the draft box keeps its size.
    @MainActor static func extraHeight(_ model: PanelModel) -> CGFloat {
        if model.editingContext {
            // Card: padding, title row, gap, editor, padding; plus the gap above it.
            return Spacing.section + Spacing.inner + Spacing.control + Spacing.item + editorHeight + Spacing.inner
        }
        return model.hasReplyContext ? Spacing.section + chipHeight : 0
    }

    var body: some View {
        if model.editingContext {
            editor
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, Spacing.section)
        } else if let context = model.replyContext, model.hasReplyContext {
            chip(context)
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, Spacing.section)
        }
    }

    private func chip(_ context: ReplyContext) -> some View {
        let details = [context.lengthLabel, context.originLabel].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: Spacing.item) {
            Button(action: model.startEditingContext) {
                HStack(spacing: Spacing.item) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Text("Replying to").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.controlText).fixedSize()
                    Text(context.preview).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: Spacing.item)
                    Text(details).font(.system(size: 12)).foregroundStyle(Theme.tertiaryText).lineLimit(1).fixedSize()
                    Kbd("⌘J")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Replying to: \(context.preview). \(details)")
            .accessibilityHint("Opens the context to edit it. Command J.")

            Button(action: model.removeContext) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.secondaryText)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove context (⇧⌘⌫)")
            .accessibilityLabel("Remove context")
        }
        .padding(.leading, Spacing.inner)
        .padding(.trailing, Spacing.item)
        .frame(height: Self.chipHeight)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.strip))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Spacing.item) {
            HStack(spacing: Spacing.item) {
                Text("What you're replying to").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.controlText)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                Spacer(minLength: 0)
                Button(action: model.useClipboardAsContext) { HStack(spacing: 6) { Text("Use clipboard"); Kbd("⇧⌘V") } }
                    .buttonStyle(SecondaryButtonStyle(height: 28))
                    .accessibilityHint("Shift Command V")
                if model.hasReplyContext {
                    Button(action: model.removeContext) { HStack(spacing: 6) { Text("Remove"); Kbd("⇧⌘⌫") } }
                        .buttonStyle(SecondaryButtonStyle(height: 28))
                        .accessibilityHint("Shift Command Delete")
                }
                Button(action: model.finishEditingContext) { HStack(spacing: 6) { Text("Done"); Kbd("⌘J") } }
                    .buttonStyle(SecondaryButtonStyle(height: 28))
                    .accessibilityHint("Command J or Escape")
            }
            .frame(height: Spacing.control)
            .padding(.horizontal, Spacing.inner)

            ZStack(alignment: .topLeading) {
                ContextEditor(text: Binding(get: { model.replyContext?.text ?? "" }, set: model.setContextText),
                              focusToken: model.contextFocusToken, onDone: model.finishEditingContext)
                if (model.replyContext?.text ?? "").isEmpty {
                    Text("Paste or type the message you're answering. It's sent as context, never rewritten.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.leading, 7)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: Self.editorHeight)
            // The text view insets its text by 7 pt, so text lines up with the title.
            .padding(.horizontal, Spacing.inner - 7)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("What you're replying to")
        }
        .padding(.vertical, Spacing.inner)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.strip))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.controlBorder))
    }

    private var subtitle: String {
        if let notice = model.contextNotice { return notice }
        guard let context = model.replyContext, model.hasReplyContext else { return "Reference only" }
        return [context.lengthLabel, context.originLabel].compactMap { $0 }.joined(separator: " · ")
    }
}

/// "Add context ⌘J" under the draft, when there's none yet.
struct ReplyContextAddButton: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        if let notice = model.contextNotice, !model.editingContext {
            Text(notice).font(.system(size: 12)).foregroundStyle(Theme.avoidText).lineLimit(1)
        } else if !model.hasReplyContext && !model.editingContext {
            Button(action: model.startEditingContext) {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left").font(.system(size: 10, weight: .semibold))
                    Text("Add what you're replying to")
                    Kbd("⌘J")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("Add what you're replying to")
            .accessibilityHint("Command J. Shift Command V uses the clipboard.")
        }
    }
}

/// Hidden buttons carrying the context shortcuts in compose.
struct ReplyContextShortcuts: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        ZStack {
            hidden("j", [.command], model.toggleContextEditor)
            hidden("v", [.command, .shift], model.useClipboardAsContext)
            hidden(.delete, [.command, .shift]) { if model.replyContext != nil { model.removeContext() } }
        }
    }

    private func hidden(_ key: KeyEquivalent, _ modifiers: EventModifiers, _ action: @escaping () -> Void) -> some View {
        Button("", action: action)
            .keyboardShortcut(key, modifiers: modifiers)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

/// The context box. ↵ or Esc goes back to the draft, ⇧↵ adds a line, ⇥ moves to the draft.
struct ContextEditor: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = NSColor(Theme.text)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.baseWritingDirection = .natural
        textView.string = text
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ContextEditor
        var focusToken = -1

        init(_ parent: ContextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                } else {
                    parent.onDone()
                }
                return true
            case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                textView.insertText("\n", replacementRange: textView.selectedRange())
                return true
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.cancelOperation(_:)):
                parent.onDone()
                return true
            default:
                return false
            }
        }
    }
}

/// Settings › General: the opt-in clipboard context, as a row in the Clipboard group.
struct ReplyContextSettings: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        FormToggle("Use the clipboard as context when it looks like a message",
                   detail: "Only text copied in the last 2 minutes, under 4,000 characters. Passwords, files and images are skipped. Takes never reads the screen or other windows.",
                   isOn: $store.settings.clipboardContext)
    }
}
