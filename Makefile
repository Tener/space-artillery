.PHONY: all test package install visuals play

all: test

test:
	./tools/factorio-test.sh mods/ space-artillery/playtest tech

package:
	./tools/package.sh

install:
	./tools/install.sh

visuals:
	./tools/capture-visuals.sh

play:
	./tools/factorio-test.sh --play mods/ space-artillery/playtest
