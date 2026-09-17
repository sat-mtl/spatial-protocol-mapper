pragma Singleton
import QtQuick

// One way of writing a scale factor, shared by the row button and the dialog.
QtObject {
    // 1.000 -> "1", 0.500 -> "0.5". toFixed always leaves a decimal point, so
    // the trailing-zero strip cannot eat the zeros of a round number.
    function number(v) {
        return Number(v).toFixed(3).replace(/\.?0+$/, "");
    }

    function isIdentity(x, y, z) {
        return x === 1 && y === 1 && z === 1;
    }

    function summary(x, y, z) {
        if (isIdentity(x, y, z))
            return "no scaling";
        return number(x) + ", " + number(y) + ", " + number(z);
    }
}
