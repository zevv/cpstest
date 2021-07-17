
# Little async socket library, supports TCP and TLS

import std/[posix]
import openssl
import cps
import types, evq, resolver

type

  Conn* = ref object
    fd*: SocketHandle
    ctx: SslCtx
    ssl: SslPtr

  DialProto = enum
    dpTcp, dpTls

proc newConn*(): Conn =
  Conn()
   

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


proc sslReadWrite(conn: Conn, r: cint) {.cps:C.} =
  let r = SSL_get_error(conn.ssl, r)
  case r:
    of SSL_ERROR_SSL:
      let err = ERR_get_error();
      echo "ssl error: ", ERR_error_string(err, nil)
    of SSL_ERROR_WANT_READ:
      iowait(conn, POLLIN)
    of SSL_ERROR_WANT_WRITE:
      iowait(conn, POLLOUT)
    else:
      echo "unknown error ", r


proc dial*(host: string, service: string, proto: DialProto = dpTcp): Conn {.cps:C.}=
  ## Dial establishes a TCP connection to the given host and service.

  # Resolve host and service
  var ress = getaddrinfo(host, service)
  let res = ress[0]

  # Create non-blocking socket and try to connect
  let fd = socket(res.ai_family, res.ai_socktype or O_NONBLOCK, 0)
  let conn = Conn(fd: fd)
  var rc = connect(fd, res.ai_addr, res.ai_addrlen)

  # non-blocking connect: backoff until POLLOUT and get the result with
  # getsockopt(SO_ERROR)
  if rc == -1 and errno == EINPROGRESS:
    iowait(conn, POLLOUT)
    var e: cint
    var s = SockLen sizeof(e)
    checkSyscall getsockopt(fd, SOL_SOCKET, SO_ERROR, addr(e), addr(s))
    if e != 0:
      raise newException(OSError, $strerror(e))
  else:
    checkSyscall rc

  # Handle SSL handshake
  if service == "https" or proto == dpTls:
    conn.ctx = SSL_CTX_new(SSLv23_client_method())
    #SSL_CTX_set_verify(conn.ctx, SSL_VERIFY_NONE, nil)
    conn.ssl = SSL_new(conn.ctx)
    discard SSL_set_fd(conn.ssl, conn.fd)
    sslSetConnectstate(conn.ssl)

    while true:
      let r = sslDoHandshake(conn.ssl)
      if r == 0:
        raise newException(OSError, $ERR_error_string(SSL_get_error(conn.ssl, r).culong, nil))
      if r == 1:
        break
      if r < 0:
        conn.sslReadWrite(r)
  conn


proc accept*(conn: Conn): Conn =
  var sa: Sockaddr_in6
  var saLen: SockLen
  let fd = posix.accept4(conn.fd, cast[ptr SockAddr](sa.addr), saLen.addr, O_NONBLOCK)
  Conn(fd: fd)


proc send*(conn: Conn, s: string): int {.cps:C.} =
  if conn.ssl != nil:
    while true:
      let r = sslWrite(conn.ssl, cast[cstring](s[0].unsafeAddr), s.len.cint)
      if r >= 0:
        result = r
        break
      else:
        conn.sslReadWrite(r)
  else:
    iowait(conn, POLLOUT)
    result = posix.send(conn.fd, s[0].unsafeAddr, s.len, 0)


proc recv*(conn: Conn, n: int): string {.cps:C.} =
  var s = newString(n)
  if conn.ssl != nil:
    while true:
      let r = sslRead(conn.ssl, cast[cstring](s[0].unsafeAddr), s.len.cint)
      if r >= 0:
        s.setLen r
        break
      else:
        conn.sslReadWrite(r)
  else:
    iowait(conn, POLLIN)
    let r = posix.recv(conn.fd, s[0].addr, n, 0)
    s.setLen if r > 0: r else: 0
  return s


proc close*(conn: Conn) =
  if conn.fd != -1.SocketHandle:
    checkSyscall posix.close(conn.fd)
    conn.fd = -1.SocketHandle

