discard """
  output: ""
"""

import ../../wheeldispatch

doAssert(not hasPendingOperations())

proc test() {.async.} =
  await sleepAsync(50)

var f = test()
while not f.finished:
  doAssert(hasPendingOperations())
  poll(10)
f.read

doAssert(not hasPendingOperations())
