import std/monotimes
import lists


const
  widthBits {.strdefine.} = 8
  numLevels = (64 + widthBits - 1) div widthBits
  numSlots = 1 shl 8
  mask = numSlots - 1


type
  Tick* = Natural

  Callback* = proc() {.gcsafe.}

  TimerEvent* = object
    finishAt*: Tick
    cb*: Callback

  TimerEventList* = DoublyLinkedList[TimerEvent]

  Timer* = object
    interval*: Tick
    ticksPending*: Tick
    now*: array[numLevels, Tick]
    slots*: array[numLevels, array[numSlots, TimerEventList]]
    head, tail: int

  Scheduler* = object
    timer: Timer

proc initScheduler*(): Scheduler =
  discard

proc initTimerEvent*(finishAt: Tick, cb: Callback): TimerEvent =
  TimerEvent(finishAt: finishAt, cb: cb)

proc setTimer*(s: var Scheduler, event: TimerEvent, levels = 0) =
  let scheduleAt = s.timer.now[levels] + event.finishAt
  s.timer.slots[0][scheduleAt].append event

proc processTimer*(s: var Scheduler, step: Tick, levels = 0) =
  var scheduleAt = s.timer.now[levels]
  for i in 0 ..< step:
    for event in s.timer.slots[levels][scheduleAt]:
      event.cb()

    inc scheduleAt
