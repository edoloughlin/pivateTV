#!/usr/bin/env bash
awk -F, '{ gsub(/"/,"",$2); print $2 }' ./logs/tv-dns.log |
  sort -u |
  awk -F. '{ for(i=NF;i>0;i--) printf "%s%s", $i, (i>1?".":"" ); print "" }' |
  sort |
  awk -F. '{ for(i=NF;i>0;i--) printf "%s%s", $i, (i>1?".":"" ); print "" }'
