import QtQuick
import ca.qc.sat.qmlcomponents

// Commits on Enter or focus loss, not per keystroke.
CustomTextField {
    id: root

    // Typing detaches the field from this; reset() reattaches it.
    property string committed: ""

    signal commit(string value)

    text: committed
    onCommittedChanged: if (!activeFocus) reset()

    // cursorPosition: a name longer than the field otherwise shows its tail.
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
