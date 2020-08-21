import lists, options
import math


const
  widthBits {.intdefine.} = 4
  total {.intdefine.} = 16
  totalBits* = 1 shl total
  # numLevels = (32 + widthBits - 1) div widthBits
  numLevels* = total div widthBits
  numSlots = 1 shl widthBits
  mask* = numSlots - 1

static:
  doAssert isPowerOfTwo(widthBits)
  doAssert isPowerOfTwo(total)

type
  Tick* = Natural

  Callback* = proc(args: pointer = nil) {.gcsafe.}

  TimerEvent* = object
    finishAt*: Tick
    timeout*: Tick # Supports repetitive events.
    repeatTimes*: int    # Supports repetitive events.
    level*: uint8        # Supports cancellation.
    scheduleAt*: uint8   # Supports cancellation.
    userData*: pointer
    cb*: Callback

  TimerEventNode* = DoublyLinkedNode[TimerEvent]

  TimerEventList* = ref object ## TODO why ref?
    data*: DoublyLinkedList[TimerEvent]
    count*: Tick

  TimerWheel* = object
    taskCounter*: Natural
    duration*: array[numLevels, Tick]
    currentTime*: Tick
    now*: array[numLevels, Tick]
    slots*: array[numLevels, array[numSlots, TimerEventList]]


proc initTimerWheel*(): TimerWheel =
  for level in 0 ..< numLevels:
    result.duration[level] = numSlots ^ (level + 1)

    for idx in 0 ..< numSlots:
      new result.slots[level][idx]

proc isActive*(s: TimerWheel): bool =
  s.taskCounter != 0

proc initTimerEvent*(cb: Callback, userData: pointer = nil): TimerEvent =
  TimerEvent(cb: cb, userData: userData)

proc `$`*(t: TimerEvent): string =
  $(t.finishAt, t.timeout)

proc slotsToString*(t: TimerWheel, level: Tick): string =
  result = "["
  let slots = t.slots[level]
  for idx in 0 ..< numSlots - 1:
    result.add $(slots[idx][]) & ", "
  result.add $(slots[^1][])
  result.add "]"

proc clear*(L: TimerEventList) =
  L.data.head = nil
  L.data.tail = nil
  L.count = 0

proc append*(L: TimerEventList, ev: TimerEventNode) {.inline.} =
  L.data.append(ev)
  inc L.count

proc internalRemove*[T](L: var DoublyLinkedList[T], n: DoublyLinkedNode[T]): bool =
  result = false

  if n == L.tail: 
    L.tail = n.prev
    result = true

  if n == L.head: 
    L.head = n.next
    result = true

  if n.next != nil: 
    n.next.prev = n.prev
    result = true

  if n.prev != nil: 
    n.prev.next = n.next
    result = true

proc remove*(L: TimerEventList, ev: TimerEventNode): bool =
  result = L.data.internalRemove(ev)
  if result:
    dec L.count

iterator mitems*(L: TimerEventList): var TimerEvent =
  for item in L.data.mitems:
    yield item

iterator items*(L: TimerEventList): TimerEvent =
  for item in L.data.items:
    yield item

iterator nodes*(L: TimerEventList): TimerEventNode =
  for item in L.data.nodes:
    yield item

template scheduleWhere(
  s: var TimerWheel, eventNode: TimerEventNode
): tuple[level: uint8, scheduleAt: uint8] =
  # mod (2 ^ n - 1)
  var level = 0'u8
  # decide which level
  let timeout = eventNode.value.finishAt - s.currentTime
  while timeout >= s.duration[level]:
    inc level

    if level >= uint8 numLevels:
      doAssert false, "Number is too large!"

  if level == 0'u8:
    (level, uint8((s.now[0] + timeout) and mask))
  else:
    (level, uint8((s.now[level] + timeout shr (widthBits * level) - 1) and mask))

proc setTimer*(s: var TimerWheel, eventNode: TimerEventNode, level, scheduleAt: uint8) {.inline.} =
  if eventNode.value.repeatTimes == 0:
    return

  eventNode.value.level = level
  eventNode.value.scheduleAt = scheduleAt

  s.slots[level][scheduleAt].append eventNode
  inc s.taskCounter

template setupTimerEvent*(s: var TimerWheel, event: var TimerEvent, 
               timeout: Tick, repeatTimes: int): TimerEventNode =
  event.repeatTimes = repeatTimes
  event.finishAt = s.currentTime + timeout
  event.timeout = timeout
  newDoublyLinkedNode(event)

template updateTimerEventNode*(s: var TimerWheel, eventNode: TimerEventNode) =
  t.value.finishAt = s.currentTime + t.value.timeout

proc setTimer*(s: var TimerWheel, eventNode: TimerEventNode) =
  ## Returns the number of TimerEvent in TimerEventList.

  let (level, scheduleAt) = scheduleWhere(s, eventNode)
  s.setTimer(eventNode, level, scheduleAt)

proc setTimer*(s: var TimerWheel, event: var TimerEvent, 
               timeout: Tick, repeatTimes: int = 1): TimerEventNode =
  ## Returns the number of TimerEvent in TimerEventList.

  result = setupTimerEvent(s, event, timeout, repeatTimes)
  s.setTimer(result)

proc cancel*(s: var TimerWheel, eventNode: TimerEventNode) =
  let (level, scheduleAt) = (eventNode.value.level, eventNode.value.scheduleAt)

  if s.slots[level][scheduleAt].remove(eventNode):
    dec s.taskCounter

proc execute*(s: var TimerWheel, t: TimerEventNode) =
  if t.value.cb != nil:
    t.value.cb(t.value.userData)

    if t.value.repeatTimes < 0:
      updateTimerEventNode(s, t)
      setTimer(s, t)
    elif t.value.repeatTimes >= 1:
      dec t.value.repeatTimes
      updateTimerEventNode(s, t)
      setTimer(s, t)

proc setDegradeTimer*(s: var TimerWheel, eventNode: TimerEventNode) =
  let (level, scheduleAt) = scheduleWhere(s, eventNode)
  s.setTimer(eventNode, level, scheduleAt)

proc degrade*(s: var TimerWheel, hlevel: Tick) =
  let 
    idx = s.now[hlevel]
    nodes = move s.slots[hlevel][idx]
  
  new s.slots[hlevel][idx]

  s.now[hlevel] = (s.now[hlevel] + 1) and mask

  for node in nodes.nodes:
    discard remove(nodes, node)
    if node.value.finishAt <= s.currentTime:
      s.execute(node)
    else:
      s.setDegradeTimer(node)

    dec s.taskCounter

template clearAndExecute(s: var TimerWheel) =
  let 
    idx = s.now[0]
    nodes = move s.slots[0][idx]

  new s.slots[0][idx]

  for node in nodes.nodes:
    discard remove(nodes, node)
    s.execute(node)
    dec s.taskCounter

template run*(s: var TimerWheel, step: Tick, all = true, tail = true) =
  for i in 0 ..< step:
    s.now[0] = (s.now[0] + 1) and mask

    when all:
      s.clearAndExecute()

    s.currentTime = (s.currentTime + 1) and (totalBits - 1)

    var hlevel = 0

    while s.now[hlevel] == 0 and hlevel < numLevels - 1:
      inc hlevel
      degrade(s, hlevel)

  when tail:
    s.clearAndExecute()

proc advance*(s: var TimerWheel, step: Tick) =
  run(s, step, true, true)

proc update*(s: var TimerWheel, step: Tick) =
  run(s, step, false, true)
