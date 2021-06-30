
# Little async socket library

import std/[posix]
import cps
import types, evq

type
  Conn* = ref object
    fd*: SocketHandle


proc listen*(port: int): Conn =
  var sa: Sockaddr_in6
  sa.sin6_family = AF_INET6.uint16
  sa.sin6_port = htons(port.uint16)
  sa.sin6_addr = in6addr_any
  var yes: int = 1
  let fd = socket(AF_INET6, SOCK_STREAM or O_NONBLOCK, 0);
  checkSyscall setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, yes.addr, sizeof(yes).SockLen)
  checkSyscall bindSocket(fd, cast[ptr SockAddr](sa.addr), sizeof(sa).SockLen)
  checkSyscall listen(fd, SOMAXCONN)
  return Conn(fd: fd)

proc dial*(host: string, port: string): Conn {.cps:C.}=
  # Resolve address
  var res: ptr AddrInfo
  var hints: AddrInfo
  hints.ai_family = AF_UNSPEC
  hints.ai_socktype = SOCK_STREAM
  away()
  let r = getaddrinfo(host, port, hints.addr, res)
  back()
  if r != 0:
    raise newException(OSError, "dial: " & $gai_strerror(r))

  # Create non-blocking socket and try to connect
  let fd = socket(res.ai_family, res.ai_socktype or O_NONBLOCK, 0)
  let conn = Conn(fd: fd)
  var rc = connect(fd, res.ai_addr, res.ai_addrlen)
  freeaddrinfo(res)

  if rc == -1 and errno == EINPROGRESS:
    # non-blocking connect: backoff until POLLOUT and get the result with getsockopt
    iowait(conn, POLLOUT)
    var e: cint
    var s = SockLen sizeof(e)
    checkSyscall getsockopt(fd, SOL_SOCKET, SO_ERROR, addr(e), addr(s))
    if e != 0:
      raise newException(OSError, $strerror(e))
  else:
    checkSyscall rc
  conn

proc accept*(conn: Conn): Conn =
  var sa: Sockaddr_in6
  var saLen: SockLen
  let fd = posix.accept4(conn.fd, cast[ptr SockAddr](sa.addr), saLen.addr, O_NONBLOCK)
  Conn(fd: fd)

proc send*(conn: Conn, s: string): int {.cps:C.} =
  iowait(conn, POLLOUT)
  let r = posix.send(conn.fd, s[0].unsafeAddr, s.len, 0)
  return r

proc recv*(conn: Conn, n: int): string {.cps:C.} =
  var s = newString(n)
  iowait(conn, POLLIN)
  let r = posix.recv(conn.fd, s[0].addr, n, 0)
  s.setLen if r > 0: r else: 0
  return s

proc close*(conn: Conn) =
  if conn.fd != -1.SocketHandle:
    checkSyscall posix.close(conn.fd)
    conn.fd = -1.SocketHandle
