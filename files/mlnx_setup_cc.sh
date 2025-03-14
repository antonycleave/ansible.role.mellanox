#!/bin/bash

function usage {

cat <<EOM
Usage: $(basename "$0") [OPTION]...

  -d          RoCE Device Name (e.g. bnxt_re0, bnxt_re_bond0)
  -i          Ethernet Interface Name (e.g. p1p1 or for bond, specify slave interfaces like -i p6p1 -i p6p2)
  -s VALUE    RoCE Packet DSCP Value
  -c [0-7]    RoCE CNP Packet Priority
  -p VALUE    RoCE CNP Packet DSCP Value
  -b VALUE    RoCE Bandwidth percentage for ETS configuration - Default is 50%
  -h          display help
EOM
exit 2
}

MAX_INTERFACE_COUNT=2

while getopts ":r:s:c:p:i:d:v:m:b:t:u:h" o; do
    case "${o}" in
        s)
            s=${OPTARG}
            ;;
        c)
            c=${OPTARG}
            ;;
        p)
            p=${OPTARG}
            ;;
        i)
            i=${OPTARG}
            ;;
        d)
            d=${OPTARG}
            ;;
        v)
            v=${OPTARG}
            ;;
        m)
            m=${OPTARG}
            ;;
        b)
            b=${OPTARG}
            ;;
        h)
            usage
            ;;

        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${i}" ] ; then
    usage
fi
if [ -z "${r}" ]; then
    r=3
fi
# if no dev set look up ib dev from /sys
if [ -z "${d}" ] ; then
  found=0
  if [ -d "/sys/class/net/$i/device/infiniband" ]; then
    for ibpath in /sys/class/net/$i/device/infiniband/*; do
      if [ -d $ibpath ]; then
        d=$(basename "$ibpath")
        found=1
      fi
    done
  fi
  if [ $found -eq 0 ]; then
    echo "no ib device specified in -d flag and unable to find a correspoing dev for $i in /sys/class/net/$i/device/infiniband/"
  fi
fi

IF_NAME=$i
DEV_NAME=$d
ROCE_DSCP=${s:-26}
ROCE_PRI=${r:-3,7}
ROCE_CNP_DSCP=${p:-48}
ROCE_CNP_PRI=${c-7}
ROCE_BW=${b:-50}
ROCE_TOS=$(( ROCE_DSCP * 4 ))
if [ $ROCE_BW -lt 100 ]
then
        L2_BW=`expr 100 - $ROCE_BW`
else
        L2_BW=50
fi


if [ "${ROCE_PRI}" -ne 3 ]; then
  echo "this script is a WIP and only 3 works now as we have is set 3 in ALL SITES"
  exit 3
fi


# use L3 PFC, default=pcp (L2 PFC)
mlnx_qos -i $IF_NAME --trust dscp

#enable PFC on PFC priority 3 and 7 ONLY
mlnx_qos -i $IF_NAME --pfc 0,0,0,1,0,0,0,1
# clear Traffic Class (TC) settings
echo "tclass=-1" > /sys/class/infiniband/$DEV_NAME/tc/1/traffic_class
# set default ToS (DSCP value * 4) for RoCE traffic
echo ${ROCE_TOS} > /sys/class/infiniband/$DEV_NAME/tc/1/traffic_class
# set default ToS for RoCE traffic
cma_roce_tos -d $DEV_NAME -t ${ROCE_TOS}
#map dscp 26 to priority 3
mlnx_qos -i $IF_NAME --dscp2prio set,26,3
#map dscp 48 to priority 7
mlnx_qos -i $IF_NAME --dscp2prio set,48,7
#this seems to be right
mlnx_qos -i $IF_NAME --tsa=ets,ets,strict,strict,strict,strict,strict,strict --tcbw=$L2_BW,$ROCE_BW,0,0,0,0,0,0
