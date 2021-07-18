
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
    var status: cint
    let r = posix.waitpid(p.pid, status, WNOHANG)
    checkSyscall r
    if r == p.pid:
      break
    else:
      sigwait SIGCHLD

  p.stdin.close()
  p.stdout.close()
  p.stderr.close()
  p.reaped = true
  debug "process " & $p.pid & " reaped"

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
    checkSyscall posix.close(fd[0][1])
    checkSyscall posix.close(fd[1][0])
    checkSyscall posix.close(fd[2][0])
    checkSyscall posix.setsid()
    # Prepare args
    var args = pargs
    args.insert cmd, 0
    let cargs = allocCStringArray(args)
    # Exec new process
    let r = posix.execv(cmd, cargs)
    posix.exitnow(-1)

  debug "process " & $pid & " started: " & cmd
  checkSyscall posix.close fd[0][0]
  checkSyscall posix.close fd[1][1]
  checkSyscall posix.close fd[2][1]

  let p = Process(
    pid: pid,
    stdin:  newConn(fd[0][1], "stdin"),
    stdout: newConn(fd[1][0], "stdout"),
    stderr: newConn(fd[2][0], "stderr"),
  )
 
  # Spawn reaper coroutine
  spawn reaper(p)
  return p


proc wait*(c: C, p: Process): C {.cpsMagic.} =
  if p.reaped:
    return c
  else:
    p.waitCont = c
