.PHONY: all test test-smoke test-demos package install visuals play

all: test

test:
	./tools/test.sh

test-smoke:
	./tools/factorio-test.sh mods/ space-artillery/playtest tech

test-demos:
	./tools/factorio-test.sh mods/ space-artillery/clips verify 120000
	./tools/factorio-test.sh mods/ space-artillery/showcase verify 55000

package:
	./tools/package.sh

install:
	./tools/install.sh

visuals:
	./tools/capture-visuals.sh

play:
	./tools/factorio-test.sh --play mods/ space-artillery/playtest
