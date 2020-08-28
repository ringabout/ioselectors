# Package

version       = "0.1.0"
author        = "flywind"
description   = "Selectors extension."
license       = "Apache-2.0"
srcDir        = "src"



# Dependencies

requires "nim >= 1.2.6"
requires "wepoll >= 0.1.0"
requires "https://github.com/xflywind/timerwheel"

task tests, "Tests all":
  exec "testament all"
