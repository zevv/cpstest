
# CPS test

This is a test project to do some "real" work with CPS to see where CPS can
shine, or to find where it is still lacking.

The goal of the code is to become a basic standalone HTTP server that can pass
continuations around between the compiled server and the Nim-js client.

## Results so far

### The good

- The quality of the CPS transformation is getting better by the day. For
  day-to-day code I have not ran into big surprises, and any issues I did find
  were often fixed within hours by the CPS authors.

- CPS in it's current state offers a nice and usable API; it allows for a very
  natural "thread like" feel, writing linear code and hiding all the gory async
  details to CPS.

- Performance of CPS is pretty good, the bottlenecks in this application are
  mostly caused by me being lazy with memory allocations and string handling,
  not by CPS.

- I like how the CPS continuation type can be used to silently carry state
  through the code without having to explicitly pass that around: in this case
  the event queue instance is part of the continuation type, and allows all cps
  code to do seamless I/O or timer handling.

### The bad

- Stack traces in CPS result in the "real" trace, typically from main() into
  the event() queue into the current continuation leg. From a users perpsective
  it would be nice if the trace could unwind over the cps 'mom' stack to give a
  better idea of "how I got there".

- Generics would come handy - I've been told these are to be expected shortly.

- At this time there is no way to create CPS "function pointers" or "closures",
  which makes it harder to compose with CPS and do things like callback
  functions or vtables. Given the nature of CPS I'm not sure if something like
  this would be feasible though.

- Compilation times: CPS compilation is becoming a bit slow. Not a show stopper
  for me yet.

### The ugly

- CPS and for loops don't play well - this is mostly a limitation of the Nim
  macro system.


## Contents

This project consists of the following parts:

- types.nim: Shared types, including the basic continuation type
- evq.nim: The core event queue for suspending continuations on I/O or timers
- conn.nim: Low level CPS async socket handling: `dial()`, `bind()`, `send()`, `recv(), `close()`
- bconn.nim: Async CPS bufferd I/O layer on top of conn. `readLine()` and friends
- http.nim: Shared http code for reading and writing http requests and responses
- httpclient.nim: Basic HTTP client
- httpserver.nim: Basic HTTP server
- main.nim: main application

## Running

nim r --gc:arc main.nim


