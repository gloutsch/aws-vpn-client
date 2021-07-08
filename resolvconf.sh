#!/bin/bash

IF_DNS_SEARCH="$(cat domains.txt | xargs)"

case $script_type in

up)
   for optionname in ${!foreign_option_*} ; do
      option="${!optionname}"
      part1=$(echo "$option" | cut -d " " -f 1)
      if [ "$part1" == "dhcp-option" ] ; then
         part2=$(echo "$option" | cut -d " " -f 2)
         part3=$(echo "$option" | cut -d " " -f 3)
         if [ "$part2" == "DNS" ] ; then
            IF_DNS_NAMESERVERS="$IF_DNS_NAMESERVERS $part3"
         fi
         if [ "$part2" == "DOMAIN" ] ; then
            IF_DNS_SEARCH="$IF_DNS_SEARCH $part3"
         fi
      fi
   done
   R=""
   if [ "$IF_DNS_SEARCH" ] ; then
           R="${R}search $IF_DNS_SEARCH
"
   fi
   for NS in $IF_DNS_NAMESERVERS ; do
           R="${R}nameserver $NS
"
   done
   echo -n "$R" | resolvconf -p -a "${dev}"
   ;;

down)
   resolvconf -d "${dev}" -f
   ;;
esac
