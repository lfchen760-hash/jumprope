#!/usr/bin/env bash
cd /root/dsh/test/jumprope
export UPLOAD_TOKEN="$(cat .upload_token)"
exec node server.js
