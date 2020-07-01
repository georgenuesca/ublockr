##!/bin/sh
# ublockr
# Licensed under GPL 3.0, Made by Toast, Jacob Salmela (Pi-Hole)
# Script made for router supporting Entware

cfg=./ublockr.cfg        # edit this if you want your cfg in a different directory
if [ -f $cfg ]; then logger "Reading ublockr config...." >&2
else logger no configuration found exiting... ; exit 0 ;fi
. $cfg

case $(grep -oE 'merlin|padavan|OpenWrt' /proc/version) in
  merlin)    path=$asuswrt_path>&2; configuration=$asuswrt_dnsmasq >&2; iface=$nic ;;
  padavan)   path=$padavan_path >&2; configuration=$padavan_dnsmasq >&2; iface=$nic ;;
  OpenWrt)   path=$openwrt_path >&2; iface=$nic ;;
  *)         path=$other_path >&2; configuration=$other_dnsmasq >&2; iface=$nic ;;
esac

# SET VARIABLES
pix_v4='192.168.0.1'
pix_v6=`'192.168.0.1'
regexp_ip=`echo "\b([0-9]{1,3}\.){3}[0-9]{1,3}\s+(([a-zA-Z0-9]+)(\-|\|_|\.)){1,8}[a-zA-Z]{2,4}((\.)[a-zA-Z]{2,4}){0,1}\b"`
regexp_no=`echo "\b(([a-zA-Z0-9]+)(\-|\|_|\.)){1,8}[a-zA-Z]{2,4}((\.)[a-zA-Z]{2,4}){0,1}\b"`
# END VARIABLES

get_lists () {
mkdir -p $path
if [ -f $path/ip.list ]; then echo; else wget -q $iplist -O $path/ip.list; fi
if [ -f $path/no.list ]; then echo; else wget -q $nolist -O $path/no.list; fi
logger -s -t ublockr updating adblock lists.
     wget -t 5 -q --show-progress -i $path/ip.list -O $path/ip.part
     wget -t 5 -q --show-progress -i $path/no.list -O $path/no.part
}

sort_lists () {
cat $path/ip.part | grep -oE "$regexp_ip" | awk '{print "127.0.0.1    " $2}' | sed "s/127\.0\.0\.1/$pix_v4/" | sort -u >$path/ipv4.part
cat $path/no.part | grep -oE "$regexp_no"| awk '{print "127.0.0.1    " $1}'| sed "s/127\.0\.0\.1/$pix_v4/" | sort -u >>$path/ipv4.part
if [ "$(cat /proc/net/if_inet6 | wc -l)" -gt "0" ]; then
cat $path/ip.part | grep -oE "$regexp_ip" | awk '{print "127.0.0.1    " $2}' | sed "s/127\.0\.0\.1/$pix_v6/" | sort -u >$path/ipv6.part
cat $path/no.part | grep -oE "$regexp_no"| awk '{print "127.0.0.1    " $1}'| sed "s/127\.0\.0\.1/$pix_v6/" | sort -u >>$path/ipv6.part
fi
}

customlist () {
cat ./custom.list >>$path/ipv4_hosts
}

whitelist () {
if [ -f $path/whitelist.filter ]; then echo; else wget -q $wlfilter -O $path/whitelist.filter; fi
if [[ -r $path/whitelist.filter ]];then
    awk -F':' '{print $1}' $path/whitelist.filter | while read -r line; do echo "$pix_v4    $line"; done > $path/whitelist_v4.part
    grep -F -x -v -f $path/whitelist_v4.part $path/ipv4.part > $path/ipv4_hosts
    if [ "$(cat /proc/net/if_inet6 | wc -l)" -gt "0" ]; then
       awk -F':' '{print $1}' $path/whitelist.filter | while read -r line; do echo "$pix_v6    $line"; done > $path/whitelist_v6.part
       grep -F -x -v -f $path/whitelist_v6.part $path/ipv6.part > $path/ipv6_hosts
    fi; fi
}

cleanup () {
rm $path/*.part
chmod 666 $path/ipv4_hosts
if [ -f $path/ipv6_hosts ]; then chmod 666 $path/ipv6_hosts; fi
}

add_config () {
case $(grep -oE 'OpenWrt' /proc/version) in
  OpenWrt) cp $path/ipv4_hosts /tmp/hosts/;
           if [ -f $path/ipv6_hosts ]; then cp $path/ipv6_hosts /tmp/hosts/;fi ;;
  *)       if grep -Fxq "addn-hosts=$path/ipv4_hosts" $configuration
           then logger -s -t ublockr ipv4_hosts is present in $configuration
           else echo "addn-hosts=$path/ipv4_hosts" >>$configuration
           logger -s -t ublockr ipv4_hosts is added to $configuration; fi
if [ -f $path/ipv6_hosts ]; then
    if grep -Fxq "addn-hosts=$path/ipv6_hosts" $configuration
    then logger -s -t ublockr ipv6_hosts is present in $configuration
    else echo "addn-hosts=$path/ipv6_hosts" >>$configuration
    logger -s -t ublockr ipv6_hosts is added to $configuration; fi; fi ;;
esac
}

dnsmasq_restart () {
case $(grep -oE 'merlin|padavan|OpenWrt' /proc/version) in
  merlin)    service restart_dnsmasq   ;;
  padavan)   kill -SIGTERM $(pidof dnsmasq) && /usr/sbin/dnsmasq   ;;
  OpenWrt)   /etc/init.d/dnsmasq restart   ;;
  *)         kill -SIGTERM $(pidof dnsmasq) && /usr/sbin/dnsmasq ;;
esac; logger -s -t ublockr reloaded dnsmasq to read in new hosts
}

summary () {
ipv4_total=$(cat $path/ipv4_hosts | wc -l)
if [ -f $path/ipv6_hosts ]; then ipv6_total=$(cat $path/ipv6_hosts | wc -l);fi
logger -s -t ublockr updated ipv4 adblock lists, $ipv4_total ads sites blocked
if [ -f $path/ipv6_hosts ]; then logger -s -t ublockr updated ipv6 adblock lists, $ipv6_total ads sites blocked; fi
}

#enable/disable here
get_lists
sort_lists
whitelist
customlist
#cleanup
#add_config
#dnsmasq_restart
summary
