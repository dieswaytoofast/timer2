APPLICATION := timer2

ERL := erl
EPATH := -pa ebin -pz deps/*/ebin
TEST_EPATH := -pa .eunit -pz deps/*/ebin

.PHONY: all doc clean test

all: compile

bootstrap:
	@rebar get-deps

compile:
	@rebar compile

deps:
	@rebar get-deps

doc:
	@rebar skip_deps=true doc

clean:
	@rebar skip_deps=true clean

depclean:
	@rebar clean

distclean:
	@rebar delete-deps

dialyze: compile
	@dialyzer -r .

test: compile
	@rebar skip_deps=true eunit

console:
	$(ERL) -sname $(APPLICATION) $(EPATH) -config app

test-console: test
	$(ERL) -sname $(APPLICATION)_test $(TEST_EPATH) -config app

