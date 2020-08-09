import lists, std/monotimes


type
  CallBack* = proc() {.gcsafe.}

  TimerCallBack* = object
    finishAt*: MonoTime
    callback*: CallBack

  Timer* = object
    callback: seq[TimerCallBack]
    head, tail: int

  Scheduler* = object
    timer: Timer
