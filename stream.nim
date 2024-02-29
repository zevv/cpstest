
import pkg/cps

import types, evq, logger


type

  ReadImpl = proc(s: Stream, n: int): string {.cps:C.}
  ReadLineImpl = proc(s: Stream): string {.cps:C.}
  WriteImpl = proc(s: Stream, data: string) {.cps:C.}
  FlushImpl = proc(s: Stream) {.cps:C.}
  EofImpl = proc(s: Stream): bool {.cps:C.}
  CloseImpl = proc(s: Stream) {.cps:C.}

  Stream* = ref object of RootObj
    fn_read*: ReadImpl
    fn_read_line*: ReadLineImpl
    fn_write*: WriteImpl
    fn_flush*: FlushImpl
    fn_eof*: EofImpl
    fn_close*: CloseImpl


proc read*(s: Stream, n: int): string {.cps:C.} =
  let cb = s.fn_read
  var c = cb.call(s, n)
  mommify c
  recover(cb, c)


proc readLine*(s: Stream): string {.cps:C.} =
  let cb = s.fn_read_line
  var c = cb.call(s)
  mommify c
  recover cb, c


proc write*(s: Stream, data: string) {.cps:C.} =
  let cb = s.fn_write
  var c = cb.call(s, data)
  mommify c


proc flush*(s: Stream) {.cps:C.} =
  let cb = s.fn_flush
  let c = cb.call(s)
  mommify c


proc eof*(s: Stream): bool {.cps:C.} =
  let cb = s.fn_eof
  var c = cb.call(s)
  mommify c
  recover cb, c


proc close*(s: Stream) {.cps:C.} =
  let cb = s.fn_close
  let c = cb.call(s)
  mommify c
  



