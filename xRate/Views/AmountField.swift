import SwiftUI
import AppKit

/// AppKit-backed numeric input. The model stores a Double; this field
/// formats it for display and parses user input back into a Double.
///
/// - When NOT focused: stringValue is set to `format(displayValue)`.
/// - When focus arrives: stringValue is reset to `format(displayValue)` so
///   the user starts editing from the clean formatted form.
/// - While focused: stringValue is left alone (the user's typed text is the
///   source of truth). Each keystroke is reported verbatim via `onUserEdit`;
///   parsing (and expression evaluation) happens in the model.
struct AmountField: NSViewRepresentable {
    let displayValue: Double
    let isFocused: Bool
    var placeholder: String = "0"
    /// Fired on every keystroke with the raw text the user has typed.
    var onUserEdit: (String) -> Void = { _ in }
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

        let formatted = ConverterModel.format(displayValue)
        // Sync stringValue from the model when:
        //  - the field is not focused (always show the clean formatted value);
        //  - the field is just gaining focus (reset stale typed text before
        //    the user starts editing).
        // While focused (lastIsFocused == true) we leave stringValue alone —
        // the user is editing and any rewrite would clobber their input.
        let justGainedFocus = isFocused && !coord.lastIsFocused
        if !isFocused || justGainedFocus {
            if nsView.stringValue != formatted {
                nsView.stringValue = formatted
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
            parent.onUserEdit(tf.stringValue)
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
/// - Fires `onClickFocus` synchronously on `mouseDown`, BEFORE AppKit's
///   focus / cell-editing path runs.
/// - Skips `selectText` during the click (no select-all flash on click).
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
