# ioselectors

![Github Action](https://github.com/xflywind/ioselectors/workflows/Test%20ioselectors/badge.svg)
[![Build Status](https://dev.azure.com/xzsflywind/xlsx/_apis/build/status/xflywind.ioselectors?branchName=master)](https://dev.azure.com/xzsflywind/xlsx/_build/latest?definitionId=8&branchName=master)
![Travis](https://travis-ci.org/xflywind/ioselectors.svg?branch=master)

![License: Apache-2.0](https://img.shields.io/github/license/xflywind/ioselectors)
[![Version](https://img.shields.io/github/v/release/xflywind/ioselectors?include_prereleases)](https://github.com/pxflywind/ioselectors/releases)


Cross platform IO engine for Nim.

Enhancements for `selectors` module in stdlib and add IOCP supports in windows.

`selectors` has little difference with stdlib's except that it adds support for windows(`registerHandle`, `updateHandle`, `registerEvent`). You can read docs in stdlib:

https://nim-lang.org/docs/selectors.html


## Installation

```
nimble install ioselectors
```
