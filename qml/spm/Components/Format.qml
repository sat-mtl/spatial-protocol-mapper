pragma Singleton
import QtQuick

// One way of writing a route or a scale, shared by the rows, the cells and the
// dialogs, so no two of them can describe the same thing differently.
QtObject {
    // 1.000 -> "1", 0.500 -> "0.5". toFixed always leaves a decimal point, so
    // the trailing-zero strip cannot eat the zeros of a round number.
    function number(v) {
        return Number(v).toFixed(3).replace(/\.?0+$/, "");
    }

    function scaleIsIdentity(x, y, z) {
        return x === 1 && y === 1 && z === 1;
    }

    function scale(x, y, z) {
        if (scaleIsIdentity(x, y, z))
            return "no scaling";
        return number(x) + ", " + number(y) + ", " + number(z);
    }

    // -1 on either bound means unbounded.
    function range(min, max) {
        if (min < 0 && max < 0)
            return "all sources";
        if (max < 0)
            return min + " and up";
        if (min < 0)
            return "1 to " + max;
        if (min === max)
            return String(min);
        return min + " to " + max;
    }

    function route(min, max, offset) {
        return range(min, max) + (offset !== 0 ? "  +" + offset : "");
    }

    // Only what differs from the default, for somewhere with no room to spell
    // out a route that is not doing anything unusual.
    function annotation(min, max, offset) {
        const ranged = (min >= 0 || max >= 0);
        if (!ranged && offset === 0)
            return "";
        if (!ranged)
            return "+" + offset;
        return range(min, max) + (offset !== 0 ? "  +" + offset : "");
    }
}
