SHELL := /bin/bash

all: clean angelspie

angelspie:
	pipenv run hy2py angelspie.hy -o angelspie_py.py
	pipenv run pex $$(pipenv run pip freeze -l) . -e angelspie_py:_main --disable-cache --inherit-path=fallback -o angelspie
	rm -f angelspie_py.py

clean:
	rm -f angelspie_py.py
	rm -f angelspie

doc:
	sed -i -e '/^## API documentation/q' README.md
	pipenv run hy angelspie.hy --docs >> README.md

test:
	xterm -class angelspie_test &
	pipenv run hy angelspie.hy --load test.as

# vim:ft=make
