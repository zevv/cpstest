
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


proc request*(client: Client, meth: string, url: string, body: string = ""): Response {.cps:C.} =
  # Request
  let req = newRequest(meth, url)
  req.contentLength = body.len
  var port = req.uri.port
  if port == "":
    port = req.uri.scheme
  let conn = conn.dial(req.uri.hostname, port)
  let bw = newBwriter(conn)
  let br = newBreader(conn)
  req.write(bw)

  if body.len > 0:
    bw.write(body)

  bw.flush()

  # Response
  var rsp = newResponse()
  rsp.read(br)
  let body = br.read(rsp.contentLength)
  
  return rsp
  
proc get*(client: Client, url: string): Response {.cps:C} =
  client.request("GET", url)

