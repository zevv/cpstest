
# Little async socket library, supports TCP, TLS and AF_UNIX
# sockets

import std/[posix, os]
import openssl
import cps
import types, evq, resolver, logger

const log_tag = "conn"

type
  ConnObj* = object
    name: string
    fd*: cint
    ctx: SslCtx
    ssl: SslPtr

  Conn* = ref ConnObj

  TlsMode = enum tlsClient, tlsServer


proc `$`*(conn: Conn | ConnObj): string =
  result.add "conn(" & $conn.fd
  if conn.ssl != nil: result.add ",ssl"
  if conn.name != "": result.add "," & conn.name
  result.add ")"


proc getName*(sa: ptr Sockaddr, salen: SockLen): string =
  var host = newString(posix.INET6_ADDRSTRLEN)
  var serv = newString(32)
  discard posix.getnameinfo(sa, salen,
                    host[0].addr, host.len.SockLen,
                    serv[0].addr, serv.len.SockLen,
                    NI_NUMERICHOST or NI_NUMERICSERV)
  if sa.sa_family.cint == AF_INET6: host = "[" & host & "]"
  result = host & ":" & serv


proc `$`*(sas: Sockaddr_storage): string =
  getName cast[ptr Sockaddr](sas.unsafeAddr), sizeof(sas).SockLen


# Handle SSL function call return codes

proc do_ssl_aux(conn: Conn, ret: cint) {.cps:C.} =
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
    do_ssl_aux(conn, ret)
  ret


proc newConn*(fd: cint = -1, name: string = ""): Conn {.cps:C.} =
  result = Conn(fd: fd, name: name)
  #ldmp "$1: new", result


proc listen*(host: string, service: string, certfile: string = ""): Conn {.cps:C.} =
  ## Bind and listen on a TCP port

  # Resolve host and service
  var res = getaddrinfo(host, service)[0]

  # Bind and listen socket
  var yes: int = 1
  let fd = socket(res.ai_family, SOCK_STREAM or O_NONBLOCK, 0)
  checkSyscall setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, yes.addr, sizeof(yes).SockLen)
  checkSyscall bindSocket(fd, res.ai_addr, res.ai_addrlen)
  checkSyscall listen(fd, SOMAXCONN)
  let name = getname(res.ai_addr, res.ai_addrlen)
  let conn = newConn(fd.cint, name)
  ldmp "$1: listen", conn

  # Create SSL context if cert given
  if certfile != "":
    conn.ctx = SSL_CTX_new(SSLv23_method())
    discard SSL_CTX_use_certificate_chain_file(conn.ctx, certFile)
    discard SSL_CTX_use_PrivateKey_file(conn.ctx, certFile, SSL_FILETYPE_PEM)

  result = conn


proc startTls*(conn: Conn, ctx: SslCtx, mode: TlsMode) {.cps:C.} =
  ## Switch the connection to TLS by adding a TLS context and performing
  ## the handshake
  assert conn.ctx == nil
  conn.ctx = ctx
  conn.ssl = SSL_new(conn.ctx)
  discard SSL_set_fd(conn.ssl, conn.fd.SocketHandle)
  if mode == tlsClient:
    sslSetConnectstate(conn.ssl)
  else:
    sslSetAcceptState(conn.ssl)
  discard do_ssl sslDoHandshake(conn.ssl)


proc connect*(conn: Conn, sa: ptr SockAddr, salen: SockLen) {.cps:C.} =
  ## Connect the conn to the given sockadder, potentially async
  ldmp "$1: connect", conn
  var rc = posix.connect(conn.fd.SocketHandle, sa, salen)
  if rc == -1 and errno == EINPROGRESS:
    iowait(conn, POLLOUT)
    var e: cint
    var s = SockLen sizeof(e)
    checkSyscall getsockopt(conn.fd.SocketHandle, SOL_SOCKET, SO_ERROR, addr(e), addr(s))
    if e != 0:
      raise newException(OSError, $strerror(e))
  else:
    checkSyscall rc


proc dial*(host: string, service: string, secure: bool): Conn {.cps:C.}=
  ## Dial establishes a TCP connection to the given host and service.
  var ress = getaddrinfo(host, service)
  let res = ress[0]
  # Create non-blocking socket
  let fd = socket(res.ai_family, res.ai_socktype or O_NONBLOCK, 0)
  let name = getname(res.ai_addr, res.ai_addrlen)
  let conn = newConn(fd.cint, name)
  # Perform connect, async
  conn.connect(res.ai_addr, res.ai_addrlen)
  # Do SSL handshake if needed
  if secure:
    let ctx = SSL_CTX_new(SSLv23_method())
    conn.startTls(ctx, tlsClient)
  result = conn


proc accept*(sconn: Conn): Conn {.cps:C.} =
  ## Accept a connection on a conn, optionally performing a TLS handshake is
  ## the socket has a TLS context
  var sa: Sockaddr_storage
  var saLen: SockLen = sizeof(sa).SockLen
  let fd = posix.accept(sconn.fd.SocketHandle, cast[ptr SockAddr](sa.addr), saLen.addr)
  checkSyscall fd.cint
  checkSyscall fcntl(fd.cint, F_SETFL, O_NONBLOCK)
  let name = getName(cast[ptr Sockaddr](sa.addr), saLen)
  var conn = newConn(fd.cint, name)
  # Setup SSL if the parent conn has a SSL context
  if sconn.ctx != nil:
    conn.startTls(sconn.ctx, tlsServer)
  ldmp "$1: accepted", conn
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


proc close*(conn: Conn) {.cps:C.} =
  # Close the conn
  if conn.fd != -1:
    ldmp "$1: close", conn
    checkSyscall posix.close(conn.fd)
    conn.fd = -1
  if conn.ssl != nil:
    SSL_free(conn.ssl)
    conn.ssl = nil

