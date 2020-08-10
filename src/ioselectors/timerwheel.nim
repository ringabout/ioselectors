import std/monotimes


type
  CallBack* = proc() {.gcsafe.}

  TimerCallBack* = object
    finishAt*: MonoTime
    callback*: CallBack

  Timer* = object
    startTime*: MonoTime
    callback*: seq[seq[TimerCallBack]]
    head, tail: int

  Scheduler* = object
    timer: Timer
