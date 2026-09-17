pragma Singleton
import QtQuick
import ca.qc.sat.qmlcomponents

// Shared by TableHeader, InputRow and OutputRow. Name is the flexible column.
QtObject {
    readonly property int toggle: 48
    readonly property int minName: 120
    readonly property int host: 120
    readonly property int port: 80
    readonly property int protocol: 195
    readonly property int route: 120
    readonly property int action: 80

    // Seven cells, six gaps, and Theme.spacing * 2 of margin at each end.
    readonly property int minimumRowWidth:
        toggle + minName + host + port + protocol + route + action
        + 6 * Theme.spacing + 4 * Theme.spacing
}
