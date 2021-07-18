
import std/[uri, strutils]
import cps
import bconn, types, conn, http

type
  Client = ref object
    maxFollowRedirects: int
    conn: Conn
    br: Breader
    bw: Bwriter

proc newClient*(): Client =
  Client(
    maxFollowRedirects: 5
  )


proc request*(client: Client, meth: string, url: string, body: string = ""): Response {.cps:C.} =

  # Build request
  let req = newRequest(meth, url)
  req.contentLength = body.len

  # Open connection and send request
  var port = req.uri.port
  if port == "":
    port = req.uri.scheme
  let secure = req.uri.scheme == "https"
  client.conn = conn.dial(req.uri.hostname, port, secure)
  client.bw = newBwriter(client.conn)
  client.br = newBreader(client.conn)
  req.write(client.bw)
  if body.len > 0:
    client.bw.write(body)
  client.bw.flush()

  # Handle response
  var rsp = newResponse()
  rsp.read(client.br)
  
  return rsp

proc readBody*(client: Client, rsp: Response): string {.cps:C.} =
  if rsp.contentLength > 0:
    # Get body with content length
    result = client.br.read(rsp.contentLength)
  elif rsp.headers.get("transfer-encoding") == "chunked":
    # Do de-chunking
    while true:
      let n = client.br.readLine().parseHexInt()
      if n == 0:
        break
      # TODO: #207
      let b = client.br.read(n)
      # TODO: #206
      let _ = client.br.readLine()
      result.add b
  
proc get*(client: Client, url: string): Response {.cps:C} =
  client.request("GET", url)

