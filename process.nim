
import std/[posix]
import cps
import types, evq, logger

const log_tag = "process"

type
  Pipe* = ref object
    fd: SocketHandle

  Process* = ref object
    pid: Pid
    stdin*: Pipe
    stdout*: Pipe
    stderr*: Pipe
    waitCont*: C
    reaped: bool


proc newPipe(fd: SocketHandle): Pipe = 
  Pipe(fd: fd)


proc write*(pipe: Pipe, s: string) {.cps:C.} =
  var o = 0
  var n = s.len
  while true:
    iowait pipe.fd, POLLOUT
    let r = posix.write(pipe.fd.cint, s[o].unsafeAddr, n)
    checkSyscall r
    inc o, r
    dec n, r
    if n == 0:
      break

proc read*(pipe: Pipe, n: int): string {.cps:C.} =
  var s = newString(n)
  iowait pipe.fd, POLLIN
  let r = posix.read(pipe.fd.cint, s[0].addr, n)
  checkSyscall r
  s.setLen if r > 0: r else: 0
  return s


proc close*(p: Pipe) =
  if p.fd != -1.SocketHandle:
    checkSyscall close p.fd
    p.fd = -1.SocketHandle


proc resumeWaiting(c: C, p: Process) {.cpsVoodoo.} =
  if p.waitCont != nil:
    c.evq.push p.waitCont


proc reaper(p: Process) {.cps:C.} =
  while true:
    sigwait SIGCHLD
    var status: cint
    let r = posix.waitpid(p.pid, status, WNOHANG)
    checkSyscall r
    if r == p.pid:
      break
  p.reaped = true
  resumeWaiting(p)


proc runProcess*(cmd: string, pargs: seq[string]): Process {.cps:C.} =

  # Create pipes for stdin/sdout/stderr
  var fd: array[3, array[2, cint]]
  for i in 0..2:
    checkSyscall posix.pipe(fd[i])

  # Fork subprocess
  let pid = posix.fork()
  checkSyscall pid

  if pid == 0:
    # Dup stdin/stdout/stderr to 0/1/2
    checkSyscall posix.dup2(fd[0][0], 0)
    checkSyscall posix.dup2(fd[1][1], 1)
    checkSyscall posix.dup2(fd[2][1], 2)
    for i in 3..4096:
      discard posix.close(i.cint)
    checkSyscall posix.setsid()
    # Prepare args
    var args = pargs
    args.insert cmd, 0
    let cargs = allocCStringArray(args)
    # Exec new process
    let r = posix.execv(cmd, cargs)
    posix.exitnow(-1)
 
  let p = Process(
    pid: pid,
    stdin:  newPipe(fd[0][1].SocketHandle),
    stdout: newPipe(fd[1][0].SocketHandle),
    stderr: newPipe(fd[2][0].SocketHandle),
  )
 
  # Spawn reaper coroutine
  spawn reaper(p)
  return p


proc wait*(c: C, p: Process): C {.cpsMagic.} =
  if p.reaped:
    return c
  else:
    p.waitCont = c
