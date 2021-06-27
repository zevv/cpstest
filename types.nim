
# Our types

import cps
import tables
import heapqueue
import posix
import deques
import macros

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
    name*: string

proc trace*(c: C, what: string, info: LineInfo) =
  echo "trace ", what, " ", info

proc pass*(cFrom, cTo: C): C =
  echo "pass"
  assert cFrom != nil
  assert cTo != nil
  cTo.evq = cFrom.evq
  cTo

template checkSyscall*(e: typed) =
  let r = e
  if r == -1:
    raise newException(OSError, "boom r=" & $r & ": " & $strerror(errno))
