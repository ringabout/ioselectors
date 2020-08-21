discard """
output: '''
testCallback()
'''
"""

import ../../wheeldispatch

proc testCallback() =
  echo "testCallback()"

when true:
  callSoon(testCallback)
  poll()
