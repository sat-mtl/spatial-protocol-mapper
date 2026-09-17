import QtQuick
import ca.qc.sat.qmlcomponents

// CustomButton at the sidebar colour is invisible on a device row. One step
// lighter, re-adding the hover that overriding `color` removes.
CustomButton {
    id: root

    color: hover.hovered ? Theme.buttonBgHover : Theme.backgroundColorTertiary
    height: Theme.buttonHeight

    HoverHandler { id: hover }
}
