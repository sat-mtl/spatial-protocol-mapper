pragma Singleton
import QtQuick

// One definition of the device-table columns, so the header, the input rows
// and the output rows cannot drift apart.
//
// Name is the flexible column; everything else is fixed. The fixed total plus
// the gaps has to leave at least `minName` at the window's minimum width.
QtObject {
    readonly property int toggle: 48
    readonly property int minName: 120
    readonly property int host: 120
    readonly property int port: 80
    readonly property int protocol: 195
    readonly property int route: 120
    readonly property int action: 80
}
