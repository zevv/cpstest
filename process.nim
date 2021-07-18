
import std/[posix, tables, os]
import cps
import types, evq, logger, conn

const log_tag = "process"

type

  ProcessCtx* = ref object
    cmd*: string
    args*: seq[string]
    env*: seq[tuple[k:string, v:string]]
    cwd*: string

  Process* = ref object
    pid: Pid
    stdin*: Conn
    stdout*: Conn
    stderr*: Conn
    waitCont*: C
    reaped: bool
    status: cint


proc resumeWaiting(c: C, p: Process) {.cpsVoodoo.} =
  if p.waitCont != nil:
    c.evq.push p.waitCont


proc reaper(p: Process) {.cps:C.} =
  while true:
    let r = posix.waitpid(p.pid, p.status, WNOHANG)
    checkSyscall r
    if r == p.pid:
      break
    else:
      sigwait SIGCHLD

  p.stdin.close()
  p.stdout.close()
  p.stderr.close()
  p.reaped = true
  debug "process $1 reaped, status: $2", p.pid, p.status

  resumeWaiting(p)


proc start*(pc: ProcessCtx): Process {.cps:C.} =

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
    # Close the other ends of the pipes
    checkSyscall posix.close(fd[0][1])
    checkSyscall posix.close(fd[1][0])
    checkSyscall posix.close(fd[2][0])
    checkSyscall posix.setsid()
    # Prepare args
    var args = pc.args
    args.insert pc.cmd, 0
    let cargs = allocCStringArray(args)
    # Prepare env
    for e in pc.env:
      os.putEnv(e.k, e.v)
    # Chdir
    if pc.cwd != "":
      checkSyscall posix.chdir(pc.cwd)
    # Exec new process
    let r = posix.execv(pc.cmd, cargs)
    posix.exitnow(-1)

  debug "process started pid: $1, cmd: '$2'", pid, pc.cmd

  checkSyscall posix.close fd[0][0]
  checkSyscall posix.close fd[1][1]
  checkSyscall posix.close fd[2][1]

  let p = Process(
    pid: pid,
    stdin:  newConn(fd[0][1], "pipe"),
    stdout: newConn(fd[1][0], "pipe"),
    stderr: newConn(fd[2][0], "pipe"),
  )
 
  # Spawn reaper coroutine
  spawn reaper(p)
  return p


proc start*(cmd: string, args: seq[string]): Process {.cps:C.} =
  let pc = ProcessCtx(cmd: cmd, args: args)
  start(pc)

proc waitAux*(c: C, p: Process): C {.cpsMagic.} =
  if p.reaped:
    return c
  else:
    p.waitCont = c

proc wait*(p: Process): cint {.cps:C.} =
  waitAux(p)
  result = p.status
