
# buo: buffered I/O implemenation.
#
# This is a layer that lies on top of a conn that can perform async buffered
# read and write and offers other convenience functions like readLine()
#
# Ideally, this should be abstracted away with some kind of vtable mechanism so
# it can also be used to read (chunked) HTTP payload or websocket streams.
# Currently this is blocked by cps bug #183

import strutils
import cps, types, conn, stream


type

  Bio* = ref object of Stream
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

#
# Bufferd I/O stream implementation
#

proc bioReadImpl(s:Stream, n: int): string {.cps:C.} =
  ## Read 'n' bytes form the bio; may return less then the requested
  ## number of bytes when the underlying conn goes EOF
  let bio = s.Bio
  while not bio.eof and bio.r.buf.len - bio.r.tail < n:
    bio.fill()

  var newTail = min(bio.r.tail+n, bio.r.buf.len)
  result = bio.r.buf[bio.r.tail..<newTail]
  bio.r.tail = newTail
  bio.shift()


proc bioReadLineImpl*(s: Stream): string {.cps:C.} =
  ## Read one line from the bio. Lines are terminated with '\n' or '\r\n'.
  result = s.Bio.readBytes('\n')
  result.stripTrailing('\n')
  result.stripTrailing('\r')


proc bioEofImpl*(s: Stream): bool {.cps:C.} =
  ## Return true if the bio is at EOF
  result = s.Bio.eof


proc bioWriteImpl*(st: Stream, s: string) {.cps:C.} =
  ## Write data to the bio buffer, potentially performing one or more writes to
  ## the underlying conn when the bio buffer size is exceeded. Returns the
  ## number of bytes written.
  let bio = st.Bio
  if not bio.eof:
    bio.w.buf.add s
    if bio.w.buf.len > bio.bufSize:
      bio.flush()


proc bioFlushImpl*(s: Stream) {.cps:C.} =
  ## Write any unbuffered data to the underlying conn
  let bio = s.Bio
  while not bio.eof and bio.w.buf.len > 0:
    let n = bio.conn.write(bio.w.buf)
    if n >= 0:
      bio.w.buf = bio.w.buf[n..^1]
    else:
      bio.eof = true
      break


proc bioCloseImpl*(s: Stream) {.cps:C.} =
  ## Close the bio, also closes the underlying conn
  s.Bio.conn.close()
  s.Bio.eof = true


func newBio*(conn: Conn, bufSize: int = 4096): Stream =
  ## Create a new bio on top of the given conn
  Bio(
    conn: conn,
    bufSize: bufSize,
    fn_read: whelp bioReadImpl,
    fn_readLine: whelp bioReadLineImpl,
    fn_eof: whelp bioEofImpl,
    fn_write: whelp bioWriteImpl,
    fn_flush: whelp bioFlushImpl,
    fn_close: whelp bioCloseImpl,
  )



