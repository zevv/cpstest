
# Our types

import std/[posix, deques, posix, heapqueue, tables, macros, locks, sets, times]
import cps

export POLLIN, POLLOUT

type
  C* = ref object of Continuation
    evq*: Evq

  EvqIo* = object
    fd*: cint
    c*: C

  EvqTimer* = object
    time*: float
    c*: C

  EvqSig* = object
    c*: C

  EvqThread* = ref object
    thread*: Thread[EvqThread]
    c*: C
    id*: int

  Evq* = ref object
    logger*: Logger                  # Logger instance
    running*: bool                   # Main event loop runs as long as this is true
    now*: float                      # The current monotime
    epfd*: cint                      # Epoll file descriptor
    evfd*: cint                      # Eventfd for signaling thread joins
    work*: Deque[C]                  # Work dequeue
    timers*: HeapQueue[EvqTimer]     # Scheduled timer continuations
    ios*: Table[cint, EvqIo]         # Scheduled I/O continuations

    thlock*: Lock                    # Protecting thwork
    thwork*: HashSet[EvqThread]      # Offloaded continuations

  # TODO: I hate it https://github.com/nim-lang/rfcs/issues/6

  LogLevel* = enum
    llDmp, llDbg, llInf, llTst, llWrn, llErr

  Logger* = ref object
    level*: LogLevel
    backends*: seq[LoggerBackend]
    queue*: Deque[LogRec]

  LogRec* = object
    level*: LogLevel
    tag*: string
    msg*: string
    time*: DateTime

  LoggerBackend* = proc(rec: LogRec)

#proc trace*(c: C; name: string; info: LineInfo) =
#  echo "trace ", name, $info

proc pass*(cFrom, cTo: C): C =
  assert cFrom != nil
  assert cTo != nil
  cTo.evq = cFrom.evq
  cTo

template checkSyscall*(e: typed) =
  let r = e
  if r == -1:
    raise newException(OSError, "boom r=" & $r & ": " & $strerror(errno))
