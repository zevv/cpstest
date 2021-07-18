
import std/[posix]
import cps
import types, evq, logger, conn

const log_tag = "process"

type

  Process* = ref object
    pid: Pid
    stdin*: Conn
    stdout*: Conn
    stderr*: Conn
    waitCont*: C
    reaped: bool

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
    stdin:  newConn fd[0][1],
    stdout: newConn fd[1][0],
    stderr: newConn fd[2][0],
  )
 
  # Spawn reaper coroutine
  spawn reaper(p)
  return p


proc wait*(c: C, p: Process): C {.cpsMagic.} =
  if p.reaped:
    return c
  else:
    p.waitCont = c
