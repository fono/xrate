import SwiftUI
import AppKit

struct AmountField: NSViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    var placeholder: String = "0"
    /// Fired synchronously on every click (before AppKit's focus handling).
    var onClickFocus: () -> Void = {}
    /// Fired for Tab (false) and Shift-Tab (true).
    var onTab: (_ reverse: Bool) -> Void = { _ in }

    private static let inputFont: NSFont = {
        let size: CGFloat = 18
        if let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: descriptor, size: size) {
            return rounded
        }
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }()

    func makeNSView(context: Context) -> NSTextField {
        let tf = ClickFocusTextField()
        tf.delegate = context.coordinator
        tf.alignment = .right
        tf.font = AmountField.inputFont
        tf.isBordered = true
        tf.bezelStyle = .roundedBezel
        tf.isBezeled = true
        tf.isEditable = true
        tf.isSelectable = true
        tf.usesSingleLineMode = true
        tf.lineBreakMode = .byClipping
        tf.cell?.wraps = false
        tf.cell?.isScrollable = true
        tf.placeholderString = placeholder
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        let coord = context.coordinator
        coord.parent = self

        if let tf = nsView as? ClickFocusTextField {
            tf.onClickFocus = { [coord] in coord.parent.onClickFocus() }
        }

        if nsView.stringValue != text {
            // Preserve selection across the text replacement so a re-render
            // (e.g. from setBase reformatting amountText) doesn't collapse a
            // selection that Tab arrival just set.
            let editor = nsView.currentEditor()
            let prevText = nsView.stringValue
            let prevSelection = editor?.selectedRange
            let prevWasFullSelection: Bool = {
                guard let r = prevSelection else { return false }
                return r.length > 0 && r.length == (prevText as NSString).length
            }()

            nsView.stringValue = text

            if let editor = nsView.currentEditor() {
                if prevWasFullSelection {
                    editor.selectAll(nil)
                } else if let prev = prevSelection {
                    let len = (text as NSString).length
                    let loc = min(prev.location, len)
                    let lenSel = min(prev.length, max(0, len - loc))
                    editor.selectedRange = NSRange(location: loc, length: lenSel)
                }
            }
        }

        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        if isFocused, !coord.lastIsFocused {
            if let window = nsView.window,
               window.firstResponder !== nsView,
               window.firstResponder !== nsView.currentEditor() {
                window.makeFirstResponder(nsView)
            }
        }
        coord.lastIsFocused = isFocused
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AmountField
        var lastIsFocused = false

        init(parent: AmountField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }

        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)):
                parent.onTab(false)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onTab(true)
                return true
            default:
                return false
            }
        }
    }
}

/// NSTextField that:
/// - Fires `onClickFocus` synchronously on `mouseDown`, BEFORE
///   `super.mouseDown` runs AppKit's focus / cell-editing logic. The caller
///   uses this to set base + focus atomically with the click.
/// - Skips `selectText` during the click (so AppKit's cell-editing path
///   doesn't briefly select all when starting to edit).
/// - Selects all on focus arrival via Tab / programmatic `makeFirstResponder`
///   (focus that does NOT come from a mouseDown).
private final class ClickFocusTextField: NSTextField {
    var onClickFocus: (() -> Void)?
    private var inMouseDown = false

    override func mouseDown(with event: NSEvent) {
        onClickFocus?()
        inMouseDown = true
        super.mouseDown(with: event)
        inMouseDown = false
    }

    override func selectText(_ sender: Any?) {
        if inMouseDown {
            // Become first responder if needed, but skip the "select all"
            // half of selectText so the click's cursor placement isn't
            // fighting an immediate selection.
            if let win = window,
               win.firstResponder !== self,
               win.firstResponder !== currentEditor() {
                win.makeFirstResponder(self)
            }
            return
        }
        super.selectText(sender)
    }

    override func becomeFirstResponder() -> Bool {
        let cameFromMouse = inMouseDown
        let result = super.becomeFirstResponder()
        if result, !cameFromMouse {
            DispatchQueue.main.async { [weak self] in
                self?.currentEditor()?.selectAll(nil)
            }
        }
        return result
    }
}
