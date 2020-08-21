discard """
  cmd:      "nim c -r --styleCheck:hint --panics:on $options $file"
  matrix:   "--gc:arc; -d:widthBits:8 -d:total:32"
  targets:  "c"
  nimout:   ""
  action:   "run"
  exitcode: 0
  timeout:  60.0
"""


include ../../src/ioselectors/timerwheel
import sugar


block:
  var s = initTimerWheel()
  var count = 0
  var event0 = initTimerEvent(proc(args: pointer = nil) = 
    inc count)


  var event1 = initTimerEvent(proc(args: pointer = nil) = discard "first")
  var event2 = initTimerEvent(proc(args: pointer = nil) = discard "second")


  discard s.setTimer(event0, 5)


  s.advance(4)
  doAssert count == 0
  s.advance(1)
  doAssert count == 1, $count


  discard s.setTimer(event1, 3)
  discard s.setTimer(event1, 7)
  discard s.setTimer(event2, 18)
  discard s.setTimer(event2, 19)
  discard s.setTimer(event2, 28)
  discard s.setTimer(event2, 29)
  discard s.setTimer(event2, 37)
  discard s.setTimer(event2, 62)

  doAssert s.taskCounter == 8, $s.taskCounter

  s.advance(17)

  doAssert s.taskCounter == 6, $s.taskCounter
  s.advance(4)
  doAssert s.taskCounter == 4, $s.taskCounter
  s.advance(8)


  doAssert s.taskCounter == 2, $s.taskCounter


block:
  var s = initTimerWheel()
  var count = 0
  var event0 = initTimerEvent(proc(args: pointer = nil) = 
    inc count)

  # Scheduler does nothing
  s.advance(10)
  doAssert count == 0
  doAssert not s.isActive

  discard s.setTimer(event0, 5, 1)
  doAssert s.isActive
  s.advance(5)
  doAssert count == 1

  s.advance(256)
  doAssert count == 1

  discard s.setTimer(event0, 5)
  s.advance(5)
  doAssert count == 2

  s.advance(250)
  discard s.setTimer(event0, 5)
  s.advance(10)
  doAssert count == 3

  discard s.setTimer(event0, 5)
  discard s.setTimer(event0, 10)

  s.advance(4)
  doAssert count == 3
  s.advance(1)
  doAssert count == 4


block:
  var s = initTimerWheel()
  var count = 0
  var event0 = initTimerEvent(proc(args: pointer = nil) = 
    inc count)

  doAssert count == 0

  discard s.setTimer(event0, 16)
  s.advance(15)
  doAssert count == 0
  s.advance(1)
  doAssert count == 1, $count

  discard s.setTimer(event0, 17)
  s.advance(16)
  doAssert count == 1
  s.advance(1)
  doAssert count == 2, $count

  discard s.setTimer(event0, 16 * 4 - 1)
  s.advance(16 * 4 - 2)
  doAssert count == 2
  s.advance(1)
  doAssert count == 3


  for i in 0 ..< 2:
    discard s.setTimer(event0, 16 * 4 + 5)
    s.advance(16 * 4 + 4)
    doAssert count == 3 + i
    s.advance(1)
    doAssert count == 4 + i


block:
  var event1 = initTimerEvent(proc(args: pointer = nil) =
    discard)

  var event2 = initTimerEvent(proc(args: pointer = nil) =
    discard)

  discard event1
  discard event2


block:
  var count0 = 0
  var count1 = 0

  var event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
  var event1a = initTimerEvent(proc(args: pointer = nil) = inc count1)
  var event1b = initTimerEvent(proc(args: pointer = nil) = inc count1)

  var s = initTimerWheel()
  discard s.setTimer(event1a, 16)
  discard s.setTimer(event1b, 16)
  s.advance(1)
  discard s.setTimer(event0, 15)
  s.advance(14)
  doAssert count0 == 0
  doAssert count1 == 0
  doAssert s.currentTime == 15

  s.advance(1)

  doAssert count0 == 1
  doAssert count1 == 2

  doAssert s.currentTime == 16

block:
  var 
    count0 = 0
    event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
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
    event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
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

  s.cancel(n4)
  s.advance(60000)
  doAssert count0 == 0

block:
  var 
    count0 = 0
    event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
    s = initTimerWheel()

  discard s.setTimer(event0, 10, -1)

  for i in 0 ..< 100:
    s.update(10)

  doAssert count0 == 100, $count0

block:
  var 
    count0 = 0
    event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
    s = initTimerWheel()

  discard s.setTimer(event0, 10, -1)

  for i in 0 ..< 100:
    s.advance(10)

  doAssert count0 == 100, $count0

block:
  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    discard s.setTimer(event0, 65534, -1)

    s.advance(70000)
    doAssert count0 == 1, $count0

  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    discard s.setTimer(event0, 65534, -1)

    s.advance(65534)
    doAssert count0 == 1, $count0

  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    discard s.setTimer(event0, 65534, -1)

    s.advance(65533)
    doAssert count0 == 0, $count0
  
  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    discard s.setTimer(event0, 65534, -1)

    s.advance(65535)
    doAssert count0 == 1, $count0

  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    discard s.setTimer(event0, 65534, -1)

    s.advance(65535)
    doAssert count0 == 1, $count0

  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    discard s.setTimer(event0, 4098, -1)

    s.advance(4098)
    doAssert count0 == 1, $count0


block:
  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    discard s.setTimer(event0, 4096, -1)

    s.advance(4096)
    doAssert count0 == 1, $count0
    s.update(4097)
    doAssert count0 == 2, $count0
    s.advance(4095)
    doAssert count0 == 3, $count0
    s.advance(4095)
    doAssert count0 == 3, $count0
    s.advance(1)
    doAssert count0 == 4, $count0

    discard s.setTimer(event0, 12, 3)
    for i in 0 ..< 3:
      s.update(12)
    doAssert count0 == 7, $count0

  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()


    discard s.setTimer(event0, 31)
    # s.advance(30)
    # doAssert count0 == 0, $count0
    # s.advance(1)
    # echo s
    # doAssert count0 == 1, $count0

    s.update(31)
    doAssert count0 == 1


  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    for i in 1 .. 100:
      discard s.setTimer(event0, i)

    # s.advance(31)
    s.advance(50)
    doAssert count0 == 50, $count0

    for i in 1 .. 50:
      s.update(1)

    doAssert count0 == 100, $count0

  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    for i in 1 .. 1000:
      discard s.setTimer(event0, i)


    s.advance(500)

    doAssert count0 == 500, $count0

    for i in 1 .. 500:
      s.update(1)

    doAssert count0 == 1000, $count0

  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    for i in 1 .. 10000:
      discard s.setTimer(event0, i)


    s.advance(5000)

    doAssert count0 == 5000, $count0

    for i in 1 .. 5000:
      s.update(1)

    doAssert count0 == 10000, $count0

  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    for i in 1 .. 10000:
      discard s.setTimer(event0, i)


    s.advance(8000)

    doAssert count0 == 8000, $count0

    for i in 1 .. 4000:
      s.update(2)

    doAssert count0 == 9000, $count0

  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    for i in 1 .. 20000:
      discard s.setTimer(event0, i * 2)


    s.advance(10000)

    doAssert count0 == 5000, $count0

    for i in 1 .. 10000:
      s.update(1)

    doAssert count0 == 10000, $count0

  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    for i in countdown(1000, 555):
      discard s.setTimer(event0, i)

    s.advance(600)
    doAssert count0 == 46, $count0

    s.advance(400)
    doAssert count0 == 446, $count0


  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    for i in 1 .. 875:
      discard s.setTimer(event0, 875)


    s.advance(875)

    doAssert count0 == 875, $count0

    s.advance(1000)

    doAssert count0 == 875, $count0


block:
  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    discard s.setTimer(event0, 783)

    s.advance(783)


    doAssert count0 == 1, $count0


  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    discard s.setTimer(event0, 65535, -1)

    s.update(65535)
    doAssert count0 == 1, $count0

  block:
    var 
      count0 = 0
      event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
      s = initTimerWheel()

    discard s.setTimer(event0, 12, 5)
    discard s.setTimer(event0, 70, -1)

    for i in 1 .. 5:
      s.update(12)
      doAssert count0 == i

    s.update(10)
    doAssert count0 == 6
