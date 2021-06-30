
# Our types

import std/[posix,deques,posix,heapqueue,tables,macros,locks]
import cps

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

  EvqThread* = ref object
    thread*: Thread[C]
    c*: C

  Evq* = ref object
    now*: float                      # The current monotime
    epfd*: cint                      # Epoll file descriptor
    work*: Deque[C]                  # Work dequeue
    timers*: HeapQueue[EvqTimer]     # Scheduled timer continuations
    ios*: Table[SocketHandle, EvqIo] # Scheduler IO continiations

    thlock*: Lock                    # protecting everything in this section
    evfd*: SocketHandle              # eventfd for signaling new work on thwork
    thwork*: seq[C]                  # new work added from threads

proc trace2*(c: C, what: string, info: LineInfo) =
  echo "trace ", what, " ", info

proc pass*(cFrom, cTo: C): C =
  assert cFrom != nil
  assert cTo != nil
  cTo.evq = cFrom.evq
  cTo

template checkSyscall*(e: typed) =
  let r = e
  if r == -1:
    raise newException(OSError, "boom r=" & $r & ": " & $strerror(errno))
