
import tables
import strutils
import std/uri

import cps

import bconn
import evq
import types
import conn
import http

type
  Client = ref object
    maxFollowRedirects: int

proc newClient*(): Client =
  Client(
    maxFollowRedirects: 5
  )


proc doRequest*(meth: string, client: Client, url: string): Response {.cps:C.} =
  let req = newRequest(meth, url)
  let conn = conn.dial(req.uri.hostname, 80)
  let bw = newBwriter(conn)
  let br = newBreader(conn)
  req.write(bw)
  var rsp = newResponse()
  rsp.read(br)
  echo $rsp
  
  return rsp
  
proc get*(client: Client, url: string): Response {.cps:C} =
  var url = url
  var follows = 0
  while follows < client.maxFollowRedirects:
    let rsp = doRequest("GET", client, url)
    let location = rsp.headers.getOrDefault("location", "")
    if location.len == 0:
      return rsp
    else:
      url = location
      inc follows
