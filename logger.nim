
import std/[times, deques, macros, strutils]
import cps
import types
import evq

when defined(isNimSkull):
  import system/io
else:
  import std/syncio


proc levelInfo(level: LogLevel): (string, string) =
  case level
    of llDmp: ("dmp", "\e[30;1m")
    of llDbg: ("dbg", "\e[22m")
    of llInf: ("inf", "\e[1m")
    of llTst: ("tst", "\e[7m")
    of llWrn: ("wrn", "\e[31m")
    of llErr: ("err", "\e[7;31m")


proc logConsole(rec: LogRec) =
  let
    (label, color) = levelInfo(rec.level)
    timestamp = rec.time.format("HH:mm:ss'.'fff")
    prefix = timestamp & " " &
             color & label & "|" &
             rec.tag.alignLeft(10) & "|"
    suffix = "\e[0m\n"

  for l in rec.msg.splitLines():
    if l.len > 0:
      stderr.write prefix & l & suffix


proc newLogger*(level: LogLevel): Logger =
  result = Logger(level: level)
  result.backends.add logConsole


proc work(l: Logger) {.cps:C.} =
  while l.queue.len > 0:
    let rec = l.queue.popLast
    for fn in l.backends:
      fn(rec)


proc log*(l: Logger, level: LogLevel, tag: string, msg: string) {.cps:C.} =
  let rec = LogRec(
    level: level,
    tag: tag,
    msg: msg,
    time: now()
  )
  l.queue.addFirst rec
  l.work()

# Logging shortcuts, working on the evq's logging context

template make(mname, mlevel: untyped) =
  template mname*(msg: string, args: varargs[string, `$`]) =
    mixin log_tag
    let l = getLogger()
    if mlevel >= l.level:
      l.log(mlevel, log_tag, msg % args)

make(dump,  llDmp)
make(debug, llDbg)
make(info,  llInf)
make(test,  llTst)
make(warn,  llWrn)
make(err,   llErr)


