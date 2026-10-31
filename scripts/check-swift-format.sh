#!/bin/sh
set -eu

exec swiftformat App Sources Tests --lint
