

import std/[posix]
import cps
import types, evq


proc getaddrinfo*(host: string, service: string): seq[AddrInfo] {.cps:C.} =
  ## Resolve host and service address

  var res: ptr AddrInfo
  var hints: AddrInfo
  hints.ai_family = AF_UNSPEC
  hints.ai_socktype = SOCK_STREAM

  defer:
    freeaddrinfo(res)

  # the getaddrinfo() call is ran on a dedicated thread so not to block
  # the CPS event queue
  onThread:
    let r = getaddrinfo(host, service, hints.addr, res)

  if r != 0:
    raise newException(OSError, $gai_strerror(r))
  
  # Convert the getaddrinfo() allocated linked-list of addrinfo into a seq
  # of addrinfo
  var a = res
  while a != nil:
    var b = a[]
    b.ai_next = nil
    result.add b
    a = a.ai_next
