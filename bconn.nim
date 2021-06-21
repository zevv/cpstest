
# Buffered connections

import cps
import types
import conn

type

  Breader* = ref object
    conn: Conn
    buf: string
    bufSize: int
    line*: string
    eof*: bool


proc newBreader*(conn: Conn, size: int = 4096): Breader =
  Breader(
    conn: conn,
    bufSize: 4096,
  )

proc fill(br: Breader, n: int) {.cps:C.} =
  br.conn.recv(n)
  br.buf.add br.conn.s
  if br.conn.s.len == 0:
    br.eof = true

proc read*(br: Breader, n: int) {.cps:C.} =
  ## Read exactly `n` bytes
  while br.buf.len < n:
    br.fill(n - br.buf.len)
  br.line = br.buf
  br.buf = ""


proc readLine*(br: Breader) {.cps:C.} =
  ## Read up to the first newline
  while true:
    let off = br.buf.find('\n')
    if off >= 0:
      br.line = br.buf[0..<off]
      br.buf = br.buf[off+1..^1]
      if br.line[^1] == '\r':
        br.line.setLen(br.line.len-1)
      return
    br.fill br.bufSize
    if br.conn.s.len == 0:
      br.line = ""
      return 



type

  Bwriter* = ref object
    conn: Conn
    buf: string
    bufSize: int
    eof*: bool


proc newBwriter*(conn: Conn, size: int = 4096): Bwriter =
  Bwriter(
    conn: conn,
    bufSize: 4096,
  )

proc flush*(bw: Bwriter) {.cps:C.} =
  ## Flush writer buffer
  bw.conn.sendFull(bw.buf)
  bw.buf.setLen(0)

proc write*(bw: Bwriter, buf: string) {.cps:C.} =
  ## Write string
  bw.buf.add buf
  if bw.buf.len >= bw.bufSize:
    bw.flush()

proc close*(bw: Bwriter) {.cps:C.} =
  ## Close writer
  bw.conn.close()
  bw.eof = true

