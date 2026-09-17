import QtQuick
import ca.qc.sat.qmlcomponents

// A field in a device row. Commits on Enter or on losing focus, never on every
// keystroke — a port is not a valid port halfway through being typed.
CustomTextField {
    id: root

    // The stored value. Typing detaches the field from it; it is reapplied
    // whenever the model changes underneath, including when a commit is
    // rejected and the old value comes back.
    property string committed: ""

    signal commit(string value)

    text: committed
    onCommittedChanged: if (!activeFocus) reset()

    // A name longer than the field would otherwise sit scrolled to its end,
    // showing "…tudio ADM" instead of the start.
    function reset() {
        text = committed;
        cursorPosition = 0;
    }

    onActiveFocusChanged: if (!activeFocus) reset()

    onEditingFinished: {
        if (text !== committed)
            root.commit(text);
        else
            reset();
    }
}
