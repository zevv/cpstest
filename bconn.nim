
# Buffered connections

import cps
import types, conn

type

  Breader* = ref object
    conn: Conn
    buf: string
    bufSize: int
    eof*: bool


proc newBreader*(conn: Conn, size: int = 4096): Breader =
  Breader(
    conn: conn,
    bufSize: 4096,
  )

proc fill(br: Breader, n: int) {.cps:C.} =
  let s = br.conn.recv(n)
  if s.len > 0:
    br.buf.add s
  else:
    br.eof = true

proc read*(br: Breader, n: int): string {.cps:C.} =
  ## Read exactly `n` bytes
  while not br.eof and br.buf.len < n:
    br.fill(n - br.buf.len)
  result = br.buf
  br.buf = ""


proc readLine*(br: Breader): string {.cps:C.} =
  ## Read up to the first newline
  while not br.eof:
    let off = br.buf.find('\n')
    if off >= 0:
      result = br.buf[0..<off]
      br.buf = br.buf[off+1..^1]
      if result[^1] == '\r':
        result.setLen(result.len-1)
      return
    else:
      br.fill br.bufSize

proc close*(br: Breader) {.cps:C.} =
  br.conn.close()
  br.eof = true

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
  let n = bw.conn.send(bw.buf)
  if n >= 0:
    bw.buf = bw.buf[n..^1]
  else:
    bw.eof = true

proc write*(bw: Bwriter, buf: string) {.cps:C.} =
  ## Write string
  bw.buf.add buf
  if bw.buf.len >= bw.bufSize:
    bw.flush()

proc close*(bw: Bwriter) {.cps:C.} =
  ## Close writer
  bw.conn.close()
  bw.eof = true

