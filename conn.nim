
# Little async socket library, supports TCP and TLS

import std/[posix, os]
import openssl
import cps
import types, evq, resolver

type

  Conn* = ref object
    fd*: cint
    ssl: SslPtr


proc newConn*(fd: cint = -1): Conn =
  Conn(fd: fd)


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
  return newConn(fd.cint)


proc handleSslRet(conn: Conn, ret: cint): int {.cps:C.} =
  let r = SSL_get_error(conn.ssl, ret)
  case r:
    of SSL_ERROR_SSL:
      let err = ERR_get_error();
      raise newException(OSError, $Err_error_string(err, nil))
    of SSL_ERROR_WANT_READ:
      iowait(conn, POLLIN)
    of SSL_ERROR_WANT_WRITE:
      iowait(conn, POLLOUT)
    of SSL_ERROR_SYSCALL:
      raiseOSError(osLastError())
    else:
      echo "unknown error ", r
  r


proc sslHandshake(conn: Conn) {.cps:C.} =
  while true:
    let ret = sslDoHandshake(conn.ssl)
    if ret == 1:
      break
    else:
      let _ = conn.handleSslRet(ret)


proc dial*(host: string, service: string, secure: bool): Conn {.cps:C.}=
  ## Dial establishes a TCP connection to the given host and service.

  # Resolve host and service
  var ress = getaddrinfo(host, service)
  let res = ress[0]

  # Create non-blocking socket and try to connect
  let fd = socket(res.ai_family, res.ai_socktype or O_NONBLOCK, 0)
  let conn = newConn(fd.cint)
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
  if service == "https" or secure:
    let ctx = SSL_CTX_new(SSLv23_method())
    conn.ssl = SSL_new(ctx)
    discard SSL_set_fd(conn.ssl, conn.fd.SocketHandle)
    sslSetConnectstate(conn.ssl)
    sslHandshake(conn)
  conn


proc accept*(sconn: Conn, certfile=""): Conn {.cps:C.} =
  var sa: Sockaddr_in6
  var saLen: SockLen
  let fd = posix.accept4(sconn.fd.SocketHandle, cast[ptr SockAddr](sa.addr), saLen.addr, O_NONBLOCK)
  checkSyscall fd.cint
  var conn = newConn(fd.cint)
  if certfile != "":
    let ctx = SSL_CTX_new(SSLv23_method())
    discard SSL_CTX_use_certificate_chain_file(ctx, certFile)
    discard SSL_CTX_use_PrivateKey_file(ctx, certFile, SSL_FILETYPE_PEM)
    conn.ssl = SSL_new(ctx)
    discard SSL_set_fd(conn.ssl, conn.fd.SocketHandle)
    sslSetAcceptState(conn.ssl)
    sslHandshake(conn)
  conn


proc write*(conn: Conn, s: string): int {.cps:C.} =
  if conn.ssl != nil:
    while true:
      let r = sslWrite(conn.ssl, cast[cstring](s[0].unsafeAddr), s.len.cint)
      if r >= 0:
        result = r
        break
      else:
        let _ = conn.handleSslRet(r)
  else:
    iowait(conn, POLLOUT)
    result = posix.write(conn.fd, s[0].unsafeAddr, s.len)


proc read*(conn: Conn, n: int): string {.cps:C.} =
  var s = newString(n)
  if conn.ssl != nil:
    while true:
      let r = sslRead(conn.ssl, cast[cstring](s[0].unsafeAddr), s.len.cint)
      if r >= 0:
        s.setLen r
        break
      else:
        let _ = conn.handleSslRet(r)
  else:
    iowait(conn, POLLIN)
    let r = posix.read(conn.fd, s[0].addr, n)
    s.setLen if r > 0: r else: 0
  return s


proc close*(conn: Conn) =
  if conn.fd != -1:
    checkSyscall posix.close(conn.fd)
    conn.fd = -1

