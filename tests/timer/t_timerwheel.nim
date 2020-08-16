include ../../src/ioselectors/timerwheel
import sugar


block:
  var s = initTimerWheel()
  var count = 0
  var event0 = initTimerEvent(proc() = 
    inc count)


  var event1 = initTimerEvent(proc() = discard "first")
  var event2 = initTimerEvent(proc() = discard "second")


  discard s.setTimer(event0, 5)
  s.advance(4)
  doAssert count == 0
  s.advance(2)
  doAssert count == 1


  # discard s.setTimer(event0, 5)
  # event0.cancel()
  # s.advance(6)


  discard s.setTimer(event1, 3)
  discard s.setTimer(event1, 7)
  discard s.setTimer(event2, 18)
  discard s.setTimer(event2, 19)
  discard s.setTimer(event2, 28)
  discard s.setTimer(event2, 29)
  discard s.setTimer(event2, 37)
  discard s.setTimer(event2, 62)
  doAssert s.taskCounter == 8
  s.advance(17)
  doAssert s.taskCounter == 6
  s.advance(4)
  doAssert s.taskCounter == 4
  s.advance(8)
  doAssert s.taskCounter == 3

block:
  var s = initTimerWheel()
  var count = 0
  var event0 = initTimerEvent(proc() = 
    inc count)

  # Scheduler does nothing
  s.advance(10)
  doAssert count == 0
  doAssert not s.isActive

  discard s.setTimer(event0, 5, 1)
  doAssert s.isActive
  s.advance(6)
  doAssert count == 1

  s.advance(256)
  doAssert count == 1

  discard s.setTimer(event0, 5)
  s.advance(6)
  doAssert count == 2

  s.advance(250)
  discard s.setTimer(event0, 5)
  s.advance(10)
  doAssert count == 3

  discard s.setTimer(event0, 5)
  discard s.setTimer(event0, 10)

  s.advance(4)
  doAssert count == 3
  s.advance(2)
  doAssert count == 4


block:
  var s = initTimerWheel()
  var count = 0
  var event0 = initTimerEvent(proc() = 
    inc count)

  doAssert count == 0

  discard s.setTimer(event0, 16)
  s.advance(15)
  doAssert count == 0
  s.advance(2)
  doAssert count == 1

  discard s.setTimer(event0, 17)
  s.advance(16)
  doAssert count == 1
  s.advance(2)
  doAssert count == 2

  discard s.setTimer(event0, 16 * 4 - 1)
  s.advance(16 * 4 - 2)
  doAssert count == 2
  s.advance(2)
  doAssert count == 3


  for i in 0 ..< 2:
    discard s.setTimer(event0, 16 * 4 + 5)
    s.advance(16 * 4 + 4)
    doAssert count == 3 + i
    s.advance(2)
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

  var s = initTimerWheel()
  discard s.setTimer(event1a, 16)
  discard s.setTimer(event1b, 16)
  s.advance(1)
  discard s.setTimer(event0, 15)
  s.advance(14)
  doAssert count0 == 0
  doAssert count1 == 0
  doAssert s.currentTime == 15

  s.advance(2)

  doAssert count0 == 1
  doAssert count1 == 2

  doAssert s.currentTime == 17

block:
  var 
    count0 = 0
    event0 = initTimerEvent(() => inc count0)
    s = initTimerWheel()

  discard s.setTimer(event0, 786)
  discard s.setTimer(event0, 8888)
  discard s.setTimer(event0, 8888)
  discard s.setTimer(event0, 7777)
  discard s.setTimer(event0, 63300)
  s.advance(456)
  s.advance(400)
  doAssert count0 == 1
  s.advance(9000)
  doAssert count0 == 4
  s.advance(60000)
  doAssert count0 == 5

block:
  var 
    count0 = 0
    event0 = initTimerEvent(() => inc count0)
    s = initTimerWheel()

  let n0 = s.setTimer(event0, 786)
  let n1 = s.setTimer(event0, 8888)
  let n2 = s.setTimer(event0, 8888)
  let n3 = s.setTimer(event0, 7777)
  let n4 = s.setTimer(event0, 63300)
  s.cancel(n0)
  s.cancel(n1)
  s.cancel(n2)
  s.advance(456)
  s.advance(400)
  doAssert count0 == 0
  s.cancel(n3)
  s.advance(9000)
  doAssert count0 == 0
  echo s.slotsToString(2)
  echo s.slotsToString(3)

  s.cancel(n4)
  echo s
  s.advance(60000)
  doAssert count0 == 0
