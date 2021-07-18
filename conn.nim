
# Little async socket library, supports TCP and TLS

import std/[posix, os]
import openssl
import cps
import types, evq, resolver, logger

const log_tag = "conn"

type
  Conn* = ref object
    fd*: cint
    ctx: SslCtx
    ssl: SslPtr


# Handle SSL function call return codes

proc handle_ssl_ret(conn: Conn, ret: cint) {.cps:C.} =
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
      warn "Unhandled ssl error, ret=" & $ret & " r=" & $r


# TODO: I'd rather make this a proc but #208

template do_ssl(stmt: typed): int =
  var ret: cint
  while true:
    ret = stmt
    if ret >= 0:
      break
    handle_ssl_ret(conn, ret)
  ret


proc newConn*(fd: cint = -1): Conn =
  Conn(fd: fd)


proc listen*(host: string, service: string, certfile: string = ""): Conn {.cps:C.} =
  debug "listening on " & host & " " & service

  # Resolve host and service
  var ress = getaddrinfo(host, service)
  let res = ress[0]
  var yes: int = 1

  # Bind and listen socket
  let fd = socket(AF_INET6, SOCK_STREAM or O_NONBLOCK, 0)
  checkSyscall setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, yes.addr, sizeof(yes).SockLen)
  checkSyscall bindSocket(fd, res.ai_addr, res.ai_addrlen)
  checkSyscall listen(fd, SOMAXCONN)
  let conn = newConn(fd.cint)

  # Create SSL context if cert given
  if certfile != "":
    conn.ctx = SSL_CTX_new(SSLv23_method())
    discard SSL_CTX_use_certificate_chain_file(conn.ctx, certFile)
    discard SSL_CTX_use_PrivateKey_file(conn.ctx, certFile, SSL_FILETYPE_PEM)

  result = conn


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
  if secure:
    conn.ctx = SSL_CTX_new(SSLv23_method())
    conn.ssl = SSL_new(conn.ctx)
    discard SSL_set_fd(conn.ssl, conn.fd.SocketHandle)
    sslSetConnectstate(conn.ssl)
    let _ = do_ssl sslDoHandshake(conn.ssl)

  result = conn


proc accept*(sconn: Conn): Conn {.cps:C.} =
  var sa: Sockaddr_in6
  var saLen: SockLen
  let fd = posix.accept4(sconn.fd.SocketHandle, cast[ptr SockAddr](sa.addr), saLen.addr, O_NONBLOCK)
  checkSyscall fd.cint
  var conn = newConn(fd.cint)
  # Setup SSL if the parent conn has a SSL context
  if sconn.ctx != nil:
    conn.ctx = sconn.ctx
    conn.ssl = SSL_new(conn.ctx)
    discard SSL_set_fd(conn.ssl, conn.fd.SocketHandle)
    sslSetAcceptState(conn.ssl)
    let _ = do_ssl sslDoHandshake(conn.ssl)
  conn


proc write*(conn: Conn, s: string): int {.cps:C.} =
  ## Write the given string to the conn. The total number of bytes written
  ## might be less then the length of `s`
  if conn.ssl != nil:
    result = do_ssl sslWrite(conn.ssl, cast[cstring](s[0].unsafeAddr), s.len.cint)
  else:
    iowait(conn, POLLOUT)
    result = posix.write(conn.fd, s[0].unsafeAddr, s.len)


proc read*(conn: Conn, n: int): string {.cps:C.} =
  # Read up to `n` bytes from the conn.
  var s = newString(n)
  var r: int
  if conn.ssl != nil:
    r = do_ssl sslRead(conn.ssl, cast[cstring](s[0].unsafeAddr), s.len.cint)
  else:
    iowait(conn, POLLIN)
    r = posix.read(conn.fd, s[0].addr, n)
  s.setLen if r > 0: r else: 0
  return s


proc close*(conn: Conn) =
  # Close the conn
  if conn.fd != -1:
    checkSyscall posix.close(conn.fd)
    conn.fd = -1

