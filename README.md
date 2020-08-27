# ioselectors

![Github Action](https://github.com/xflywind/ioselectors/workflows/Test%20ioselectors/badge.svg)
[![Build Status](https://dev.azure.com/xzsflywind/xlsx/_apis/build/status/xflywind.ioselectors?branchName=master)](https://dev.azure.com/xzsflywind/xlsx/_build/latest?definitionId=8&branchName=master)
![Travis](https://travis-ci.org/xflywind/ioselectors.svg?branch=master)

![License: Apache-2.0](https://img.shields.io/github/license/xflywind/ioselectors)
[![Version](https://img.shields.io/github/v/release/xflywind/ioselectors?include_prereleases)](https://github.com/pxflywind/ioselectors/releases)
[![buy me a coffee](https://img.shields.io/badge/donate-buy%20me%20a%20coffee-orange.svg)](https://github.com/planety/prologue#donate)

Cross platform IO engine and timer for Nim.

Enhancements for `selectors` module in stdlib and add IOCP supports in windows.

`selectors` has little difference with stdlib's except that it adds support for windows(`registerHandle`, `updateHandle`, `registerEvent`). You can read docs in stdlib:

https://nim-lang.org/docs/selectors.html

`Timer` is based on timerwheel which is high performance and scales well. It needs more space than timer based on heap.

## Status
- [x] Selectors
- [x] Timer
- [x] DelayQueue

## Installation

```
nimble install ioselectors
```
