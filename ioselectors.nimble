# Package

version       = "0.2.0"
author        = "ringabout"
description   = "Selectors extension."
license       = "Apache-2.0"
srcDir        = "src"



# Dependencies

requires "nim >= 1.2.6"
requires "wepoll >= 0.1.2"

task tests, "Tests all":
  exec "testament all"
