
import std/[times, deques, macros, strutils]

import cps
import types

type

  LogLevel* = enum
    llDmp, llDbg, llInf, llTst, llWrn, llErr

  Logger* = ref object
    level: LogLevel
    backends: seq[LoggerBackend]
    fn: LoggerBackend
    queue: Deque[LogRec]

  LogRec = object
    level: LogLevel
    tag: string
    msg: string
    time: DateTime

  LoggerBackend = proc(rec: LogRec)



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
             color & label & " " & 
             rec.tag.alignLeft(10) & " "
    suffix = "\e[0m"

  for l in rec.msg.splitLines():
    if l.len > 0:
      echo prefix & l & suffix


proc newLogger*(level: LogLevel): Logger =
  Logger(
    level: level,
    fn: logConsole,
  )


proc work(l: Logger) {.cps:C.} =
  while l.queue.len > 0:
    let rec = l.queue.popLast
    l.fn(rec)


proc log*(l: Logger, level: LogLevel, tag: string, msg: string) {.cps:C.} =
  let rec = LogRec(
    level: level,
    tag: tag,
    msg: msg,
    time: now()
  )
  l.queue.addFirst rec
  l.work()


proc log_if*(l: Logger, lvl: LogLevel, tag: string, msg: string) {.cps:C.} =
  if lvl >= l.level:
    l.log(lvl, tag, msg)


template make(mname, mlevel: untyped) =
  template mname*(l: Logger, msg: string) =
    mixin log_tag
    log_if(l, mlevel, log_tag, msg)

make(dump,  llDmp)
make(debug, llDbg)
make(info,  llInf)
make(test,  llTst)
make(warn,  llWrn)
make(err,   llErr)

