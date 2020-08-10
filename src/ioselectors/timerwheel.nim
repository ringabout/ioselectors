import std/monotimes
import lists


type
  CallBack* = proc() {.gcsafe.}

  TimerCallBack* = object
    finishAt*: MonoTime
    callback*: CallBack

  TimerCallBackList* = SinglyLinkedList[TimerCallBack]

  Timer* = object
    startTime*: Natural
    interval*: Natural
    first*: array[60, TimerCallBackList]
    others*: array[5, array[60, TimerCallBackList]]
    head, tail: int

  Scheduler* = object
    timer: Timer
