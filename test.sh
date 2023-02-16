#!/bin/bash
xterm -class angelspie_test &
pipenv run hy angelspie.hy --load test.as
