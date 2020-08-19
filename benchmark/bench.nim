import times
import random


import ../src/ioselectors/timerwheel



const N = 100000

randomize(124)


var s = initTimerWheel()

var cb = proc() = discard

var ev = initTimerEvent(cb)

var x: array[N, int]
for i in 0 ..< N:
  x[i] = rand(1 .. 65534)

let t = now()
for i in 0 ..< N:
  discard s.setTimer(ev, x[i])

echo now() - t
