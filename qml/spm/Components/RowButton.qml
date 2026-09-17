import QtQuick
import ca.qc.sat.qmlcomponents

// CustomButton rests at the sidebar colour, which is also the device-row
// colour, so a button inside a row would be invisible. One step lighter, with
// the hover it loses by overriding that binding.
CustomButton {
    id: root

    color: hover.hovered ? Theme.buttonBgHover : Theme.backgroundColorTertiary
    height: Theme.buttonHeight

    HoverHandler { id: hover }
}
