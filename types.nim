
# Our types

import cps
import tables
import heapqueue
import posix
import deques

export POLLIN, POLLOUT

type
  C* = ref object of Continuation
    evq*: Evq

  EvqIo* = object
    fd*: SocketHandle
    c*: C

  EvqTimer* = object
    time*: float
    c*: C

  Evq* = ref object
    now*: float
    epfd*: cint
    work*: Deque[C]
    timers*: HeapQueue[EvqTimer]
    ios*: Table[SocketHandle, EvqIo]

proc pass*(cFrom, cTo: C): C =
  cTo.evq = cFrom.evq
  cTo

template checkSyscall*(e: typed) =
  let r = e
  if r == -1:
    raise newException(OSError, "boom r=" & $r & ": " & $strerror(errno))
