discard """
  cmd:      "nim c -r --styleCheck:hint --panics:on $options $file"
  matrix:   "-d:widthBits:8; -d:widthBits:8 -d:total:32"
  targets:  "c"
  nimout:   ""
  action:   "run"
  exitcode: 0
  timeout:  60.0
"""

import ../../wheeldispatch, os, times

proc doubleSleep(hardSleep: int) {.async.} =
  await sleepAsync(50)
  sleep(hardSleep)

template assertTime(target, timeTook: float): untyped {.dirty.} =
  assert(timeTook*1000 > target - 1000, "Took too short, should've taken " &
    $target & "ms, but took " & $(timeTook*1000) & "ms")
  assert(timeTook*1000 < target + 1000, "Took too long, should've taken " &
    $target & "ms, but took " & $(timeTook*1000) & "ms")

var
  start: float
  fut: Future[void]

# NOTE: this uses poll(3000) to limit timing error potential.
start = epochTime()
fut = sleepAsync(40) and sleepAsync(100) and doubleSleep(20)
while not fut.finished:
  poll(1000)
assertTime(150, epochTime() - start)

start = epochTime()
fut = sleepAsync(40) and sleepAsync(100) and doubleSleep(50)
while not fut.finished:
  poll(1000)
assertTime(200, epochTime() - start)

start = epochTime()
fut = sleepAsync(40) and sleepAsync(100) and doubleSleep(20) and sleepAsync(200)
while not fut.finished:
  poll(1000)
assertTime(300, epochTime() - start)

start = epochTime()
fut = (sleepAsync(40) and sleepAsync(100) and doubleSleep(20)) or sleepAsync(300)
while not fut.finished:
  poll(1000)
assertTime(150, epochTime() - start)
