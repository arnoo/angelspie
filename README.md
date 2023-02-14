An ugly hack that's a mostly drop-in replacement for devilspie which now segfaults way too often. 

I did not find all thay i wanted in devilspie2 or kspie, and was sad to replace lisp with lua.

This is written in [hy](http://hylang.org/). Any hy function or macro can be used in the configuration script.

The devilspie functions i was not using are not implemented but should not be too hard to hack based on the others. You'll get a warning when yoir configuration script calls an undefined function. I welcome pull requests in the hope of making this at some point a complete drop-in replacement for devilspie. Unfortunately, devilspie has virtually no test suite, which would have been nice as a compatibility insurance.

To run, use `pipenv run hy angelspie.hy` in the source directory. It will read all .ds files in your ~/.devilspie folder and execute them for each new window (and all existing windows on run).
