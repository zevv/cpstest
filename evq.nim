
# Minimal event queue implementation supporting a work queue, I/O and timers


import std/[tables,heapqueue,deques,posix,epoll,monotimes,locks,sets]
import cps
import types

proc eventfd(count: cuint, flags: cint): cint 
  {.cdecl, importc: "eventfd", header: "<sys/eventfd.h>".}

proc newEvq*(): Evq =
  var evq = Evq(
    now: getMonoTime().ticks.float / 1.0e9,
    epfd: epoll_create(1),
    evfd: eventfd(0, 0).SocketHandle,
  )
  var ee = EpollEvent(events: POLLIN.uint32, data: EpollData(u64: evq.evfd.uint64))
  checkSyscall epoll_ctl(evq.epfd, EPOLL_CTL_ADD, evq.evfd, ee.addr)
  initlock evq.thlock
  return evq

template `<`(a, b: EvqTimer): bool =
  a.time < b.time

proc push*(evq: Evq, c: C) =
  ## Push work to the back of the work queue
  assert c != nil
  assert evq != nil
  c.evq = evq
  evq.work.addLast c

proc iowait*[T](c: C, conn: T, events: int): C {.cpsMagic.} =
  ## Suspend continuation until I/O event triggered
  assert c != nil
  assert c.evq != nil
  c.evq.ios[conn.fd] = EvqIo(fd: conn.fd, c: c)
  var ee = EpollEvent(events: events.uint32, data: EpollData(u64: conn.fd.uint64))
  checkSyscall epoll_ctl(c.evq.epfd, EPOLL_CTL_ADD, conn.fd.cint, ee.addr)

proc sleep*(c: C, delay: float): C {.cpsMagic.} =
  ## Suspend continuation until timer expires
  assert c != nil
  assert c.evq != nil
  c.evq.timers.push EvqTimer(c: c, time: c.evq.now + delay)

proc jield*(c: C): C {.cpsMagic.} =
  ## Suspend continuation until the next evq iteration - cooperative schedule.
  c.evq.timers.push EvqTimer(c: c, time: c.evq.now)

proc threadFunc(t: EvqThread) {.thread.} =
  var c = t.c
  while c.running:
    c = c.fn(c).C

proc threadOut*(c: C): C {.cpsMagic.} =
  withLock c.evq.thLock:
    var t = EvqThread(c: c)
    c.evq.thwork.incl t
    createThread(t.thread, threadFunc, t)

proc threadBack*(c: C): C {.cpsMagic.} =
  c.evq.thlock.acquire
  var sig = 1.uint64
  checkSyscall write(c.evq.evfd.cint, sig.addr, sig.sizeof)
  c.evq.thlock.release

template onThread*(code: untyped) =
  ## Move the continuation to a fresh spawned thread and trampoline it there
  threadOut()
  code
  threadBack()

proc getEvq*(c: C): Evq {.cpsVoodoo.} =
  ## Retrieve event queue for the current contiunation
  c.evq

proc updateNow(evq: Evq) =
  evq.now = getMonoTime().ticks.float / 1.0e9

proc calculateTimeout(evq: Evq): cint =
  evq.updateNow()
  result = -1
  if evq.timers.len > 0:
    let timer = evq.timers[0]
    result = cint(1000 * (timer.time - evq.now))
    result = max(result, 0)

proc handleWork(evq: Evq) =
  # Trampoline all work
  while evq.work.len > 0:
    discard trampoline(evq.work.popFirst)

proc handleTimers(evq: Evq) =
  evq.updateNow()
  while evq.timers.len > 0 and evq.timers[0].time <= evq.now:
    evq.push evq.timers.pop.c

proc handleEventFd(evq: Evq, fd: cint) =
  var sig: uint64
  checkSyscall read(fd, sig.addr, sig.sizeof)
  var done: seq[EvqThread]
  withLock evq.thlock:
    for t in evq.thwork:
      if not t.thread.running:
        done.add t
    for t in done:
      joinThread t.thread
      evq.push t.c
      evq.thwork.excl t

proc handleIoFd(evq: Evq, fd: SocketHandle) =
  let io = evq.ios[fd]
  checkSyscall epoll_ctl(evq.epfd, EPOLL_CTL_DEL, io.fd.cint, nil)
  evq.ios.del fd
  evq.push io.c

proc run*(evq: Evq) =
  
  ## Run the event queue
  while true:

    handleWork(evq)

    # Calculate timeout until first timer
    var timeout = evq.calculateTimeout()

    # Wait for timers or I/O
    var es: array[8, EpollEvent]
    let n = epoll_wait(evq.epfd, es[0].addr, es.len.cint, timeout)

    evq.handleTimers()

    # Handle ready file descriptors
    for i in 0..<n:
      let fd = es[i].data.u64.SocketHandle
      if fd == evq.evfd:
        handleEventFd(evq, evq.evfd.cint)
      else:
        handleIoFd(evq, fd)

