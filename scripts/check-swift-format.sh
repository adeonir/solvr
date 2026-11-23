#!/bin/sh
set -eu

exec swiftformat App Core CoreTests AppTests --lint
