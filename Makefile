SHELL := /bin/bash

all: doc

doc:
	sed -i -e '/^## API documentation/q' README.md
	pipenv run hy angelspie.hy --docs >> README.md

test:
	xterm -class angelspie_test &
	pipenv run hy angelspie.hy --load test.as

# vim:ft=make
