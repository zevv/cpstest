
# Our types

import std/[posix,deques,posix,heapqueue,tables,macros,locks,sets]
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
    thread*: Thread[EvqThread]
    c*: C
    id*: int

  Evq* = ref object
    now*: float                      # The current monotime
    epfd*: cint                      # Epoll file descriptor
    evfd*: SocketHandle              # Eventfd for signaling thread joins
    work*: Deque[C]                  # Work dequeue
    timers*: HeapQueue[EvqTimer]     # Scheduled timer continuations
    ios*: Table[SocketHandle, EvqIo] # Scheduler IO continiations

    thlock*: Lock                    # Protecting thwork
    thwork*: HashSet[EvqThread]      # Offloaded continuations

proc pass*(cFrom, cTo: C): C =
  assert cFrom != nil
  assert cTo != nil
  cTo.evq = cFrom.evq
  cTo

template checkSyscall*(e: typed) =
  let r = e
  if r == -1:
    raise newException(OSError, "boom r=" & $r & ": " & $strerror(errno))
