#!/bin/sh


#
# sample policy routing script for batman
# written by <lindner_marek@yahoo.de>
#
# WARNING: It just prints the possible ip commands and does nothing else !
#          If you intend to use it you have to manipulate the routing table or nothing will work.
#

LOG_FILE="route.log"
echo "" > $LOG_FILE

while read method action mtype dst mask gw src_ip ifi_prio dev table
 do
    if [ "$method" == "ROUTE" ]
       then
          if [ "$mtype" == "UNICAST" ]
             then
                echo "ip route $action $dst/$mask via $gw src $src_ip dev $dev table $table" >> $LOG_FILE
          elif [ "$mtype" == "THROW" ]
             then
                echo "ip route $action throw $dst/$mask table $table" >> $LOG_FILE
          elif [ "$mtype" == "UNREACH" ]
              then
                 echo "ip route $action unreachable $dst/$mask table $table" >> $LOG_FILE
          else
                echo "Unknown ROUTE method: $mtype" >> $LOG_FILE
          fi
    fi
 
    if [ "$method" == "RULE" ]
       then
          if [ "$mtype" == "DST" ]
             then
                echo "ip rule $action to $dst/$mask prio $ifi_prio table $table" >> $LOG_FILE
             elif [ "$mtype" == "SRC" ]
                 then
                    echo "ip rule $action from $dst/$mask prio $ifi_prio table $table" >> $LOG_FILE
             elif [ "$mtype" == "IIF" ]
                  then
                     echo "ip rule $action iif $dev prio $ifi_prio table $table" >> $LOG_FILE
             else
                echo "Unknown RULE method: $mtype" >> $LOG_FILE
          fi
    fi
 done
 
 