#!/bin/bash
#
# What this script for:
# Script imports sessions usually stored at Torque \.tripLogs dir at your device
# into MySQL database used by Open Torque Viewer
#
# USAGE:
# 1. Copy this script somewhere
# 2. Copy entire directory with triplogs from your Android device (usually located at .\.torque\tripLogs,
#    contains sessions subdirs like \tripLogs\1478946224041, and may be hidden) somewhere near the script
# 3. Run the script and provide path to tripLogs directory, e.g.:
#    import_triplogs.sh your_path_to\tripLogs
#
# LIMITATIONS:
# 1. Script not inserts sessions already presented in database. Remove it from tripLogs dir (or from DB it's up to you)
# 2. Script expects: your trackLog.csv is in default format and contains at least these columns (with following order):
#    GPS Time, Device Time, Longitude, Latitude,GPS Speed(km/h) ...
# 3. Script parses and puts into DB only these values: Latitude, Longitude, Speed (GPS) and notices (if presented)
#
#
# (c) Adel-S
#


if [[ -z $1 ]]; then echo "No tripLogs directory provided. Usage: import_triplogs.sh path_to_triplogs_dir"; exit 1; fi

triplogsdir=$1

# Fill this section with your own settings
v='8'           # usually is 8
id=''           # your torque id
eml=''          # your email

mysql_host=''   # mysql host to connect to
mysql_user=''   # mysql user (need to have INSERT and UPDATE permissions
mysql_pass=''   # mysql password
mysql_db=''     # torque database

mysql_bin='/usr/bin/mysql'

# Credentials file. Will be deleted after script finishes
mysql_creds_file='/tmp/import_triplogs.cnf'
echo -e "[client]\nuser = $mysql_user\npassword = $mysql_pass\nhost = $mysql_host" > $mysql_creds_file


# Check everything before start working
if [[ ! $($mysql_bin --defaults-extra-file=$mysql_creds_file -sN $mysql_db -e "SHOW TABLES;") ]]; then echo "MySQL: Can't connect to MySQL."; exit 1; else echo "MySQL: OK"; fi
if [[ ! -d $triplogsdir ]]; then echo "Source directory: Not exists or inaccessible."; exit 1; else echo "Source directory: OK"; fi
sessions_count=$(ls $triplogsdir | grep -P '\d{13}' | wc -l)
if [[ -z ${sessions_count} || ${sessions_count} == 0 ]]; then echo "Sessions found: none"; exit 1; else echo "Sessions found: $sessions_count"; fi


# Check if some sessions already present in database
echo "Checking duplicate sessions (already exists in database):"
mysql_sessions=$($mysql_bin --defaults-extra-file=$mysql_creds_file $mysql_db -e 'select session from sessions order by time asc;')
dir_sessions=$(ls $triplogsdir | grep -P '\d{13}' | sort -n)
for session in ${dir_sessions[@]}; do if [[ $mysql_sessions =~ "$session" ]] ; then result+=($session); fi; done
if [[ ! -z ${result[@]} ]]; then echo "Duplicated session(s): ${result[@]}"; exit 1; else echo "Duplicated sessions found: 0";fi


# Check if all files presented in sessions dir
echo "Checking nesessary files (profile.properties and trackLog.csv) exist in session dirs..."
for session in ${dir_sessions[@]}; do
 if [[ $(ls -lA $triplogsdir/$session/* | grep -P '((\bprofile\.properties\b)|(\btrackLog\.csv\b))' | wc -l) != 2 ]]
 then
   echo "Missing files in $session"; error="true"
 else echo -n "$session - "`echo "$session" | grep -Po '\d{10}' | xargs -i date -d @{} +"%Y-%m-%d %m:%H:%S"`" - OK - "
   session_size=$(cat $triplogsdir/$session/trackLog.csv | wc -l); session_size=$((session_size - 1))
   echo $session_size
 fi
done
if [[ ! -z ${error} ]]; then exit 1; fi


# Ok, everything seems fine, we are ready to go
for session in ${dir_sessions[@]}; do
 echo ""
 echo "-- Session: $session"
 session_size=$(cat $triplogsdir/$session/trackLog.csv | wc -l); session_size=$((session_size - 1))
 if [[ "$session_size" == "0" ]]; then echo "-- Session is empty. Skipping."; else


   echo "Importing session..."
   gpstime=$(head -2 $triplogsdir/$session/trackLog.csv | tail -1 | awk -F ',' '{print $1}')
   timestart=$(head -2 $triplogsdir/$session/trackLog.csv | tail -1 | awk -F ',' '{print $1}' | xargs -i date -d "{}" +"%s")"000"
   timeend=$(tail -n1 $triplogsdir/$session/trackLog.csv | awk -F ',' '{print $1}' | xargs -i date -d "{}" +"%s")"000"
   profilename=$(grep -P "profile=.*" $triplogsdir/$session/profile.properties | awk -F '=' '{print $2}')
   mysql_query="INSERT INTO sessions (v, id, session, sessionsize, time, eml, profileName, timestart, timeend) VALUES ('$v', '$id', '$session', '$row_inserted', '$timestart', '$eml', '$profilename', '$timestart', '$timeend');"
   # echo $mysql_query
   $mysql_bin --defaults-extra-file=$mysql_creds_file $mysql_db -e "$mysql_query"


   echo -n "Import raw data"
   cat $triplogsdir/$session/trackLog.csv | while read line
   do
    time=$(echo $line | awk -F ',' '{print $1}')
    if [[ "$time" != "GPS Time" ]]; then
      time=$(echo $line | awk -F ',' '{print $1}' | xargs -i date -d "{}" +"%s""000")
      lon=$(echo $line | awk -F ',' '{print $3}' | grep -oP '\d+\.\d{0,4}') # We need no more than 4 digits after the decimal point in latitude/longitude
      lat=$(echo $line | awk -F ',' '{print $4}' | grep -oP '\d+\.\d{0,4}')
      gps_speed=$(echo $line | awk -F ',' '{print $5}' | grep -oP '\d+\.\d{0,4}') # Rounding speed to 4 digits after the decimal point
      #We don't need duplicated data from exactly the same place
      if [[ "$lon" != "$prev_lon" && "$lat" != "$prev_lat" ]]; then
        mysql_query="INSERT INTO raw_logs (v, session, id, time, eml, profileName, kff1001, kff1005, kff1006) VALUES ('$v', '$session', '$id', '$time', '$eml', '$profilename', '$gps_speed', '$lon', '$lat');"
        # echo $mysql_query
        $mysql_bin --defaults-extra-file=$mysql_creds_file $mysql_db -e "$mysql_query"
        prev_lon=$lon
        prev_lat=$lat
        echo -n "."
      else
       echo -n "_"
      fi
    fi
   done
   rows_inserted=$($mysql_bin --defaults-extra-file=$mysql_creds_file -sN $mysql_db -e "SELECT count(*) FROM raw_logs WHERE session='$session';")
   echo
   echo "Done. $rows_inserted of $session_size rows inserted (excluding duplicates)"
   $mysql_bin --defaults-extra-file=$mysql_creds_file -sN $mysql_db -e "UPDATE sessions SET sessionsize='$rows_inserted' WHERE session='$session';"


   echo -n "Import notices data"
   #Manually create "Trip started" notice
   first_datapoint=$($mysql_bin --defaults-extra-file=$mysql_creds_file -sN $mysql_db -e "SELECT time, kff1006, kff1005 FROM raw_logs WHERE session='$session' ORDER BY time ASC LIMIT 1;")
   time=$(echo $first_datapoint | awk '{print$1}')
   lat=$(echo $first_datapoint | awk '{print$2}')
   lon=$(echo $first_datapoint | awk '{print$3}')
   notice="Trip started"
   notice_class="org.prowl.torque.map.notices.TripNotice"
   mysql_query="INSERT INTO raw_logs (v, session, id, time, eml, profileName, notice, noticeClass, kff1005, kff1006) VALUES ('$v', '$session', '$id', '$time', '$eml', '$profilename', '$notice', '$notice_class', '$lon', '$lat');"
   $mysql_bin --defaults-extra-file=$mysql_creds_file $mysql_db -e "$mysql_query"
   echo -n "."

   if [[ -f $triplogsdir/$session/notices.csv ]]; then
     cat $triplogsdir/$session/notices.csv | while read line
     do
       time=$(echo $line | awk -F ',' '{print $1}')
       notice_class=$(echo $line | awk -F ',' '{print $2}')
       lat=$(echo $line | awk -F ',' '{print $3}')
       lon=$(echo $line | awk -F ',' '{print $4}')
       notice=$(echo $line | awk -F ',' '{print $5}')
       mysql_query="INSERT INTO raw_logs (v, session, id, time, eml, profileName, notice, noticeClass, kff1005, kff1006) VALUES ('$v', '$session', '$id', '$time', '$eml', '$profilename', '$notice', '$notice_class', '$lon', '$lat');"
       # echo $mysql_query
       $mysql_bin --defaults-extra-file=$mysql_creds_file $mysql_db -e "$mysql_query"
       echo -n "."
     done
   fi
 fi
done
echo

#Cleanup
rm -f $mysql_creds_file