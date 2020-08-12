import lists
import math


const
  widthBits {.intdefine.} = 4
  total {.intdefine.} = 16
  totalBits = 2 ^ total
  # numLevels = (32 + widthBits - 1) div widthBits
  numLevels = total div widthBits
  numSlots = 1 shl widthBits
  mask = numSlots - 1

assert isPowerOfTwo(widthBits)

type
  Tick* = Natural

  Callback* = proc() {.gcsafe.}

  TimerEvent* = object
    finishAt: Tick
    cb*: Callback

  TimerEventList* = DoublyLinkedRing[TimerEvent]

  Timer* = object
    duration*: array[numLevels, Tick]
    currentTime*: Tick
    now*: array[numLevels, Tick]
    slots*: array[numLevels, array[numSlots, TimerEventList]]

  Scheduler* = object
    taskCounter: Natural
    timer: Timer

proc initScheduler*(): Scheduler =
  for level in 0 ..< numLevels:
    result.timer.duration[level] = numSlots ^ (level + 1)

proc isActive*(s: Scheduler): bool =
  s.taskCounter != 0

proc initTimerEvent*(cb: Callback): TimerEvent =
  TimerEvent(cb: cb)

proc `$`*(t: TimerEvent): string =
  $(t.finishAt, )

# proc cancel*(t: var TimerEvent) =
#   t.cb = nil

proc execute*(t: TimerEvent) =
  if t.cb != nil:
    t.cb()

proc setTimer*(s: var Scheduler, event: var TimerEvent, timeout: Tick) =
  # mod (2 ^ n - 1)
  var level = 0
  # decide which level
  while timeout >= s.timer.duration[level]:
    inc level

    if level >= numLevels:
      doAssert false, "Number is too large "

  event.finishAt = s.timer.currentTime + timeout

  let scheduleAt = 
    if level == 0:
      event.finishAt and mask
    else:
      (s.timer.now[level] + (timeout div s.timer.duration[level - 1]) - 1) and mask

  s.timer.slots[level][scheduleAt].append event
  inc s.taskCounter

proc degradeTimer*(s: var Scheduler, hlevel: Tick) =
  let idx = s.timer.now[hlevel] - 1

  if idx >= 0:
    for event in s.timer.slots[hlevel][idx].mitems:
      if event.finishAt <= s.timer.currentTime:
        event.execute()
      else:
        s.setTimer(event, event.finishAt - s.timer.currentTime)
      dec s.taskCounter
    s.timer.slots[hlevel][idx].head = nil

proc processTimer*(s: var Scheduler, step: Tick) =
  let level = 0

  var scheduleAt = s.timer.now[level]

  # if s.taskCounter > 0:
  for i in 0 ..< step:
    for event in s.timer.slots[level][scheduleAt]:
      event.execute()
      dec s.taskCounter

    s.timer.slots[level][scheduleAt].head = nil

    scheduleAt = (scheduleAt + 1) and mask

    var hlevel = level + 1

    if scheduleAt == 0 and hlevel < numLevels - 1:
      s.timer.now[hlevel] = (s.timer.now[hlevel] + 1) and mask
      degradeTimer(s, hlevel)

      while s.timer.now[hlevel] == 0 and hlevel < numLevels - 1:
        inc hlevel
        s.timer.now[hlevel] = (s.timer.now[hlevel] + 1) and mask
        degradeTimer(s, hlevel)

    s.timer.currentTime = (s.timer.currentTime + 1) and (totalBits - 1)


  s.timer.now[level] = scheduleAt


when isMainModule:
  import sugar

  block:
    var s = initScheduler()
    var count = 0
    var event0 = initTimerEvent(proc() = 
      inc count)


    var event1 = initTimerEvent(proc() = discard "first")
    var event2 = initTimerEvent(proc() = discard "second")


    s.setTimer(event0, 5)
    s.processTimer(4)
    doAssert count == 0
    s.processTimer(2)
    doAssert count == 1


    # s.setTimer(event0, 5)
    # event0.cancel()
    # s.processTimer(6)


    s.setTimer(event1, 3)
    s.setTimer(event1, 7)
    s.setTimer(event2, 18)
    s.setTimer(event2, 19)
    s.setTimer(event2, 28)
    s.setTimer(event2, 29)
    s.setTimer(event2, 37)
    s.setTimer(event2, 62)
    doAssert s.taskCounter == 8
    s.processTimer(17)
    doAssert s.taskCounter == 6
    s.processTimer(4)
    doAssert s.taskCounter == 4
    s.processTimer(8)
    doAssert s.taskCounter == 3

  block:
    var s = initScheduler()
    var count = 0
    var event0 = initTimerEvent(proc() = 
      inc count)

    # Scheduler does nothing
    s.processTimer(10)
    doAssert count == 0
    doAssert not s.isActive

    s.setTimer(event0, 5)
    doAssert s.isActive
    s.processTimer(6)
    doAssert count == 1

    s.processTimer(256)
    doAssert count == 1

    s.setTimer(event0, 5)
    s.processTimer(6)
    doAssert count == 2

    s.processTimer(250)
    s.setTimer(event0, 5)
    s.processTimer(10)
    doAssert count == 3

    s.setTimer(event0, 5)
    s.setTimer(event0, 10)

    s.processTimer(4)
    doAssert count == 3
    s.processTimer(2)
    doAssert count == 4


  block:
    var s = initScheduler()
    var count = 0
    var event0 = initTimerEvent(proc() = 
      inc count)

    doAssert count == 0

    s.setTimer(event0, 16)
    s.processTimer(15)
    doAssert count == 0
    s.processTimer(2)
    doAssert count == 1

    s.setTimer(event0, 17)
    s.processTimer(16)
    doAssert count == 1
    s.processTimer(2)
    doAssert count == 2

    s.setTimer(event0, 16 * 4 - 1)
    s.processTimer(16 * 4 - 2)
    doAssert count == 2
    s.processTimer(2)
    doAssert count == 3


    for i in 0 ..< 2:
      s.setTimer(event0, 16 * 4 + 5)
      s.processTimer(16 * 4 + 4)
      doAssert count == 3 + i
      s.processTimer(2)
      doAssert count == 4 + i


  block:
    var event1 = initTimerEvent(proc() =
      discard)

    var event2 = initTimerEvent(proc() =
      discard)

    discard event1
    discard event2


  block:
    var count0 = 0
    var count1 = 0

    var event0 = initTimerEvent(() => inc count0)
    var event1a = initTimerEvent(proc() = inc count1)
    var event1b = initTimerEvent(proc() = inc count1)

    var s = initScheduler()
    s.setTimer(event1a, 16)
    s.setTimer(event1b, 16)
    s.processTimer(1)
    s.setTimer(event0, 15)
    s.processTimer(14)
    doAssert count0 == 0
    doAssert count1 == 0
    doAssert s.timer.currentTime == 15

    s.processTimer(2)

    doAssert count0 == 1
    doAssert count1 == 2

    doAssert s.timer.currentTime == 17

  block:
    var 
      count0 = 0
      event0 = initTimerEvent(() => inc count0)
      s = initScheduler()

    s.setTimer(event0, 786)
    s.setTimer(event0, 8888)
    s.setTimer(event0, 8888)
    s.setTimer(event0, 7777)
    s.setTimer(event0, 63300)
    s.processTimer(456)
    s.processTimer(400)
    doAssert count0 == 1
    s.processTimer(9000)
    doAssert count0 == 4
    s.processTimer(60000)
    doAssert count0 == 5
