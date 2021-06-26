
# Little async socket library

import cps
import posix

import types
import evq

type
  Conn* = ref object
    evq*: Evq
    fd*: SocketHandle


proc listen*(evq: Evq, port: int): Conn =
  var sa: Sockaddr_in6
  sa.sin6_family = AF_INET6.uint16
  sa.sin6_port = htons(port.uint16)
  sa.sin6_addr = in6addr_any
  var yes: int = 1
  let fd = socket(AF_INET6, SOCK_STREAM, 0);
  checkSyscall setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, yes.addr, sizeof(yes).SockLen)
  checkSyscall bindSocket(fd, cast[ptr SockAddr](sa.addr), sizeof(sa).SockLen)
  checkSyscall listen(fd, SOMAXCONN)
  return Conn(evq: evq, fd: fd)

proc dial*(evq: Evq, ip: string, port: int): Conn =
  var res: ptr AddrInfo
  var hints: AddrInfo
  hints.ai_family = AF_UNSPEC
  hints.ai_socktype = SOCK_STREAM
  let r = getaddrinfo(ip, $port, hints.addr, res)
  if r == 0:
    let fd = socket(res.ai_family, res.ai_socktype, 0)
    checkSyscall connect(fd, res.ai_addr, res.ai_addrlen)
    freeaddrinfo(res)
    Conn(evq: evq, fd: fd)
  else:
    raise newException(OSError, "dial: " & $gai_strerror(r))

proc accept*(conn: Conn): Conn =
  var sa: Sockaddr_in6
  var saLen: SockLen
  let fd = posix.accept4(conn.fd, cast[ptr SockAddr](sa.addr), saLen.addr, O_NONBLOCK)
  Conn(fd: fd, evq: conn.evq)

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



