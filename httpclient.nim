
import std/[uri, strutils]
import cps
import types, conn, http, bio

type
  Client = ref object
    maxFollowRedirects: int
    conn: Conn
    bio: Bio

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
  client.bio = newBio(client.conn)
  req.write(client.bio)
  if body.len > 0:
    client.bio.write(body)
  client.bio.flush()

  # Handle response
  var rsp = newResponse()
  rsp.read(client.bio)
  
  return rsp

proc readBody*(client: Client, rsp: Response): string {.cps:C.} =
  if rsp.contentLength > 0:
    # Get body with content length
    result = client.bio.read(rsp.contentLength)
  elif rsp.headers.get("transfer-encoding") == "chunked":
    # Do de-chunking
    while true:
      let n = client.bio.readLine().parseHexInt()
      if n == 0:
        break
      result.add client.bio.read(n)
      discard client.bio.readLine()
  
proc get*(client: Client, url: string): Response {.cps:C} =
  client.request("GET", url)

