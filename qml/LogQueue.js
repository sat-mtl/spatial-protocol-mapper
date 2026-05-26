.pragma library

// Bounded FIFO drained by Engine.flushLogs. Overflow drops the oldest entry.

var CAPACITY = 2000;

var ring = new Array(CAPACITY);
var head = 0;
var tail = 0;
var count = 0;

function push(message) {
    if (count === CAPACITY) {
        head = (head + 1) % CAPACITY;
        count--;
    }
    ring[tail] = message;
    tail = (tail + 1) % CAPACITY;
    count++;
}

function pushInput(message)  { push(message); }
function pushOutput(message) { push(message); }

function hasWork() {
    return count > 0;
}

function drainUpTo(maxLines) {
    var out = [];
    var n = Math.min(maxLines, count);
    for (var i = 0; i < n; i++) {
        out.push(ring[head]);
        head = (head + 1) % CAPACITY;
        count--;
    }
    return out;
}

function clear() {
    head = 0; tail = 0; count = 0;
}
