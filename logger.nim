
import std/[times, deques, macros, strutils]
import cps
import types
import evq


proc levelInfo(level: LogLevel): (string, string) =
  case level
    of llDmp: ("dmp", "\e[33m")
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
    suffix = "\e[0m"

  var n = 0
  for l in rec.msg.splitLines():
    if l.len > 0:
      echo prefix & l & suffix


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


template make(mname, mlevel: untyped) =
  template mname*(l: Logger, msg: string) =
    mixin log_tag
    if mlevel >= l.level:
      l.log(mlevel, log_tag, msg)

make(dump,  llDmp)
make(debug, llDbg)
make(info,  llInf)
make(test,  llTst)
make(warn,  llWrn)
make(err,   llErr)
