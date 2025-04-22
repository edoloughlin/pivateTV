#!/usr/bin/env bash
while read -r ip; do
  printf "\n=== %s ===\n" "$ip"

  # 1) PTR lookup
  ptr=$(dig +short -x "$ip" | sed 's/\.$//')
  if [ -n "$ptr" ]; then
    echo "PTR: $ptr"
  else
    echo "PTR: (none)"
  fi

  # 2) WHOIS: grab org or netname
  whois "$ip" | awk -F: '
    /^(OrgName|org-name|netname|descr)[[:space:]]*:/ {
      print toupper($1)": "gensub(/^ +| +$/,"","g",$2)
      exit
    }
  '

done < $1
