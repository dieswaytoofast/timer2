timer2
======

Erlang application which is a high(er) performance and API compatible version of timer.
(just timer2:... instead of timer:...)


Requirements
------------

You should only need a somewhat recent version of Erlang/OTP, though the module
has only been tested with Erlang R15B and R15B01.


Installation
------------

To initialize the project run `make bootstrap`.

To compile the module run `make`.

To run the unit tests run `make test`.

To enter a console run `make console`.


Usage
-----

`timer2:start()` will start up the timer. (Take a look at `src/timer2.erl` to see the list of applications that need to be started though!)

In app.config you can adjust the number of acceptors and processors based on need (see below)

`timer2:add_child(timer2_acceptor | timer2_processor)` can be used to dynamically increase capacity



Details
-------

`timer` works perfectly well, as long as you don't stress it.  Its implemented as a `gen_server`,
and uses the `{reply, Timeout}` feature to deal with the timer functionality.  It also plays some
fun games with ETS and ordered_sets to figure out what should happen next. All well and good, except that its
pretty easy to overload it, especially if the timer requests come fast and furious.

`timer2`, on the other hand, works differently.  It is basically a wrapper around `erlang:send_after` 
as per [the Common Caveats in the Erlang Efficiency Guide](http://www.erlang.org/doc/efficiency_guide/commoncaveats.html#id61120).

Structurally, there are two sets of `gen_servers`, `acceptors` and `processors`.  The `acceptors` are responsible
for accepting timer2: requests (who would-a thunk it!), and all the associated housekeeping.  The `processors` 
basically _do_ stuff - sending messages or spawning MFAs at the appropriate time.

As you might imagine, the `acceptor` is the one most likely to get overloaded.  A good rule of thumb for high_performance 
is to increase the number of `acceptors` as your load/need increases. 
You should rarely need more than one or two `processors` though.
