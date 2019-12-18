#!/bin/sh

echo Content-type: text/html
echo

test "$QUERY_STRING" = "4filter" && iptables-save -t filter
test "$QUERY_STRING" = "4nat" && iptables-save -t nat
test "$QUERY_STRING" = "4mangle" && iptables-save -t mangle
test "$QUERY_STRING" = "4raw" && iptables-save -t raw
