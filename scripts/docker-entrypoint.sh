#!/bin/sh
set -eu
/app/bin/robinahs_shop eval 'RobinahsShop.Release.setup()'
exec /app/bin/robinahs_shop start
