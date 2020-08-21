discard """
  output: 42
"""

import ../../wheeldispatch

proc foo(): Future[int] {.async.} =
  template ret() = return 42
  ret()

echo (waitFor foo())
