
import std/[uri]
import cps
import bconn, types, conn, http

type
  Client = ref object
    maxFollowRedirects: int

proc newClient*(): Client =
  Client(
    maxFollowRedirects: 5
  )


proc doRequest*(meth: string, client: Client, url: string): Response {.cps:C.} =
  # Request
  let req = newRequest(meth, url)
  var port = req.uri.port
  if port == "":
    port = req.uri.scheme
  let conn = conn.dial(req.uri.hostname, port)
  let bw = newBwriter(conn)
  let br = newBreader(conn)
  req.write(bw)
  bw.flush()

  # Response
  var rsp = newResponse()
  rsp.read(br)
  
  return rsp
  
proc get*(client: Client, url: string): Response {.cps:C} =
  var url = url
  var follows = 0
  while follows < client.maxFollowRedirects:
    let rsp = doRequest("GET", client, url)
    let location = rsp.headers.get("location")
    if location.len == 0:
      return rsp
    else:
      url = location
      inc follows

