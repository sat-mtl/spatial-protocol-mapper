import QtQuick
import ca.qc.sat.qmlcomponents

// A field in a device row. Commits on Enter or on losing focus, never on every
// keystroke — a port is not a valid port halfway through being typed.
CustomTextField {
    id: root

    // The stored value. Typing detaches the field from it; it is reapplied
    // when the model changes underneath, and on losing focus.
    property string committed: ""

    signal commit(string value)

    text: committed
    onCommittedChanged: if (!activeFocus) reset()

    // Without the rewind, a name longer than the field sits scrolled to its end.
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
