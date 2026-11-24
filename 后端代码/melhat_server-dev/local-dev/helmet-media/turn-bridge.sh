#!/bin/sh
# coturn maps an advertised allocation back to its private address when two
# peers use the same relay. Whitelist only this dedicated TURN container.
set -eu
umask 077
source_conf=/etc/helmet-turn.conf
conf=/run/helmet-turn/turn.conf
public=$(awk -F= '/^external-ip=/{print $2}' "$source_conf")
set -- $(hostname -i)
[ "$#" -eq 1 ] || { echo 'TURN requires one dedicated IPv4 bridge' >&2; exit 1; }
private=$1
valid_ipv4() {
  awk -v ip="$1" 'BEGIN {
    if (split(ip,a,".") != 4) exit 1
    for (i=1;i<=4;i++) if (a[i] !~ /^[0-9]+$/ || a[i]+0>255) exit 1
  }'
}
valid_ipv4 "$public" && valid_ipv4 "$private" || { echo 'Unexpected TURN addresses' >&2; exit 1; }
case "$private" in
  10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) ;;
  *) echo 'TURN relay must be on its private container bridge' >&2; exit 1 ;;
esac
awk '!/^(external-ip|listening-ip|relay-ip)=/' "$source_conf" > "$conf"
printf '\nlistening-ip=%s\nrelay-ip=%s\nexternal-ip=%s/%s\n' "$private" "$private" "$public" "$private" >> "$conf"
exec turnserver -c "$conf"
