#!/bin/sh

set -e

http_proxy="$1"

if [ -n "${http_proxy}" ]; then
  cat <<EOAPTPROXY > /etc/apt/apt.conf.d/11http-proxy
Acquire::http::Proxy "${http_proxy}";
EOAPTPROXY
fi
