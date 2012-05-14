timer2
======

Erlang application which is a high(er) performance version of timer, which is completely API compatible.
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

`timer2:start()` will start up the timer.
(Take a look at `src/timer2.erl` to see the list of applications that need to be started though!)


Details
-------


