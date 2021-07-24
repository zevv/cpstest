
# buo: buffered I/O implemenation.
#
# This is a layer that lies on top of a conn that can perform async buffered
# read and write and offers other convenience functions like readLine()
#
# Ideally, this should be abstracted away with some kind of vtable mechanism so
# it can also be used to read (chunked) HTTP payload or websocket streams.
# Currently this is blocked by cps bug #183

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
  ## Create a new bio on top of the given conn
  Bio(conn: conn, bufSize: bufSize)


proc close*(bio: Bio) {.cps:C.} =
  ## Close the bio, also closes the underlying conn
  bio.conn.close()
  bio.eof = true


proc fill(bio: Bio) {.cps:C.} =
  # Read one chunk from the conn, append to the read buffer
  let s = bio.conn.read(bio.bufSize)
  if s.len > 0:
    bio.r.buf.add s
  else:
    bio.eof = true
  

proc shift(bio: Bio) {.cps:C.} =
  # Discard the 0..head part of the bio read buffer if the buffer
  # size is exceeded
  if bio.r.tail > bio.bufSize:
    bio.r.buf = bio.r.buf[bio.r.tail..^1]
    bio.r.tail = 0


proc stripTrailing(s: var string, c: char) =
  # Strip trailing character
  if s.len > 0 and s[^1] == c:
    s.setlen(s.len-1)


proc readBytes*(bio: Bio, delim: char): string {.cps:C.} =
  ## Ready bytes from the bio up to and including the given the delimiter.
  while not bio.eof:
    var o = bio.r.buf.find(delim, bio.r.tail)
    if o >= 0:
      result = bio.r.buf[bio.r.tail..o]
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
  ## Read one line from the bio. Lines are terminated with '\n' or '\r\n'.
  result = bio.readBytes('\n')
  result.stripTrailing('\n')
  result.stripTrailing('\r')


proc read*(bio: Bio, n: int): string {.cps:C.} =
  ## Read 'n' bytes form the bio; may return less then the requested
  ## number of bytes when the underlying conn goes EOF
  while not bio.eof and bio.r.buf.len - bio.r.tail < n:
    bio.fill()

  var newTail = min(bio.r.tail+n, bio.r.buf.len)
  result = bio.r.buf[bio.r.tail..<newTail]
  bio.r.tail = newTail
  bio.shift()


proc flush*(bio: Bio) {.cps:C.} =
  ## Write any unbuffered data to the underlying conn
  while not bio.eof and bio.w.buf.len > 0:
    let n = bio.conn.write(bio.w.buf)
    if n >= 0:
      bio.w.buf = bio.w.buf[n..^1]
    else:
      bio.eof = true
      break


proc write*(bio: Bio, s: string): int {.cps:C.} =
  ## Write data to the bio buffer, potentially performing one or more writes to
  ## the underlying conn when the bio buffer size is exceeded. Returns the
  ## number of bytes written.
  if not bio.eof:
    bio.w.buf.add s
    if bio.w.buf.len > bio.bufSize:
      bio.flush()
    return s.len
  else:
    return 0


