#!/bin/sh
set -eu

exec swiftformat --lint --recursive App Sources Tests
