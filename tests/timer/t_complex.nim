include ../../src/ioselectors/timerwheel
import sugar


block:
  var
    count0 = 0
    count1 = 0
    event0 = initTimerEvent(proc(args: pointer = nil) = inc count0)
    event1a = initTimerEvent(proc(args: pointer = nil) = inc count1)
    event1b = initTimerEvent(proc(args: pointer = nil) = inc count1)
    s = initTimerWheel()

  discard s.setTimer(event1a, 256)
  discard s.setTimer(event1b, 256)

  s.advance(1)
  discard s.setTimer(event0, 255)
  s.update(254)

  doAssert count0 == 0
  doAssert count1 == 0

  doAssert s.currentTime == 255
