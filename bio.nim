
import strutils
import cps, types, conn


type

  Bio* = ref object
    conn: Conn
    bufSize: int
    r: BioReader
    w: BioWriter
    eof*: bool

  BioReader = object
    buf: string
    tail: int

  BioWriter = object
    buf: string


func newBio*(conn: Conn, bufSize: int = 4096): Bio =
  Bio(conn: conn, bufSize: bufSize)


proc close*(bio: Bio) {.cps:C.} =
  bio.conn.close()
  bio.eof = true


proc fill(bio: Bio) {.cps:C.} =
  let s = bio.conn.read(bio.bufSize)
  if s.len > 0:
    bio.r.buf.add s
  else:
    bio.eof = true
  

proc shift(bio: Bio) {.cps:C.} =
  if bio.r.tail > bio.bufSize:
    bio.r.buf = bio.r.buf[bio.r.tail..^1]
    bio.r.tail = 0


proc readBytes*(bio: Bio, delim: char): string {.cps:C.} =
  while not bio.eof:
    var o = bio.r.buf.find(delim, bio.r.tail)
    if o >= 0:
      result = bio.r.buf[bio.r.tail..<o]
      bio.r.tail = o+1
      bio.shift()
      break
    else:
      bio.fill()
      if bio.eof:
        result = bio.r.buf[bio.r.tail..^1]
        bio.r.buf = ""
        bio.r.tail = 0
        break


proc readLine*(bio: Bio): string {.cps:C.} =
  result = bio.readBytes('\n')
  if result.len > 0 and result[^1] == '\r':
    result.setlen(result.len-1)


proc read*(bio: Bio, n: int): string {.cps:C.} =
  while not bio.eof and bio.r.buf.len - bio.r.tail < n:
    bio.fill()

  var newTail = min(bio.r.tail+n, bio.r.buf.len)
  result = bio.r.buf[bio.r.tail..<newTail]
  bio.r.tail = newTail
  bio.shift()


proc flush*(bio: Bio) {.cps:C.} =
  while not bio.eof and bio.w.buf.len > 0:
    let n = bio.conn.write(bio.w.buf)
    if n >= 0:
      bio.w.buf = bio.w.buf[n..^1]
    else:
      bio.eof = true
      break


proc write*(bio: Bio, s: string) {.cps:C.} =
  bio.w.buf.add s
  if bio.w.buf.len > bio.bufSize:
    bio.flush()


