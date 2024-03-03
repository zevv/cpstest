
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
  s.fn_read(s, n)


proc readLine*(s: Stream): string {.cps:C.} =
  s.fn_read_line(s)


proc write*(s: Stream, data: string) {.cps:C.} =
  s.fn_write(s, data)


proc flush*(s: Stream) {.cps:C.} =
  s.fn_flush(s)


proc eof*(s: Stream): bool {.cps:C.} =
  s.fn_eof(s)


proc close*(s: Stream) {.cps:C.} =
  s.fn_close(s)
  



