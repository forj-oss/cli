#!/bin/bash
#vim: setlocal ft=sh:
RST="\e[0m"
RED="\e[31m"
BLU="\e[34m"
GRE="\e[92m"

# (c) Copyright 2014 Hewlett-Packard Development Company, L.P.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

NOW=$(date +%Y-%m-%d.%H%M%S)
logpath=~/.ssh/
DB=~/hosts
#key_path=~/.ssh/
#key_path=~/.hpcloud/keypairs/
init_config=~/ssh_init
key="nova.pem"

if [ ! -f $DB ]; then
	cat > $DB <<'EOF'

#Custom Servers - (Won't be deleted when updating list)
#<name.id>         <public ip>       <date>           <key>

#### Below list are updated

EOF
fi

##No parameters sent
if (( $# < 1 )); then
	echo -e "${RED}Error, no parameter was sent.$RST"
	echo "Use this script as:"
	echo "  -rm <id> : Removes all nodes that match the id."
	echo "  -f <text>: Finds the text in the log files."
	echo "  -u       : Updates the hosts list querying nova server."
	echo "  -l       : Lists the current hosts."
	echo "  <IP>     : Connects directly to the IP using default key"
	echo "<id> <name>: Queries the hosts list looking for the id and name."
	echo -e "\n ${GRE}OPTIONS${RST}"
	echo "  -i {par} : Applies initialization script to the server."
	exit 1
fi

if [ $1 == '-i' ]; then
	if [ ! -f $init_config ]; then
		echo "${RED}Error, config file: $init_config does not exists."
		exit 1
	fi
	shift
	is_init='true'
fi

#Finds text in logs
if [ $1 == '-f' ]; then
	grep --include=*.log -rnw $logpath -e "$2" --color=always
	exit 0
fi

if [ $1 == '-rm' ] && [ "$2" != '' ]; then
	echo "Removing $2..."
	cat $DB | grep -iE "[a-z]+\.$2" --color=always
	sed -i -E "/[a-z]+\.$2/d" $DB
	exit 0
fi

##Just Lists the hosts db
if [ $1 == '-l' ]; then
	echo "List of hosts:"
	if [ "$2" != "" ]; then #kit
		result=$(cat $DB | grep -iE "\.$2" --color=always)
	else #All Maestros
		result=$(cat $DB | grep -E "maestro\.")
	fi
	echo "$result"
	exit 0
fi

##Just list the hosts db
if [ $1 == '-u' ]; then
	linenum=$(cat $DB | grep -E -n "#### Below list are updated" | awk -F: '{print $1}')
	old_serversnum=$(tail -n +$linenum $DB | grep -E " .*\..* " | wc -l)

	sed -i -n '/\#\#\#\# Below list are updated/q;p' $DB
	sed -i '/^$/d' $DB
	echo -e "\n#### Below list are updated" >> $DB

	hpcloud servers | awk -F"\|" '{print $3","$6","$9","$7}' | awk -F, '{print $1$3$4$5}' >> $DB
	echo -e "\033[1;32m$DB Updated\033[00m"
	linenum=$(cat $DB | grep -E -n "#### Below list are updated" | awk -F: '{print $1}')
	new_serversnum=$(tail -n +$linenum $DB | grep -E " .*\..* " | wc -l)
	diff=$(echo "$new_serversnum - $old_serversnum" | bc)
	echo "Old Servers: $old_serversnum, New Servers: $new_serversnum, Diff: $diff"
	exit 0
fi

#parameter is IP
if [[ $1 =~ ([0-9]{1,3}\.){3}[0-9]{1,3} ]]; then
	ip=$1
	#Check if has URL and clean it if so
	if [[ $ip =~ 'http' ]]; then
		ip=$(echo "$ip" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
	fi
	#Check if IP exists in db and show info
	host_name=$(cat $DB | grep $ip | awk '{print $1}')
	if [[ "$host_name" != "" ]]; then
		echo -e "Host: \033[33m$host_name${RST}"
	fi
	message="$ip"
#parameter is ID NODE
else
	id=$1
	node=$2

	if [ "$node" == "" ]; then
		echo -e "${RED}Error, no server name sent.$RST"
		exit 1
	fi

	#Alias handling
	alias=$(cat ~/hosts | grep -iE '^alias:' | grep -iE ' '$node | awk '{print $2}')
	if [ "$alias" != "" ] && [ "$alias" != "$node" ]; then
		echo "Using alias $node, converting to $alias"
		node=$alias
	fi

	ip=$(cat $DB | grep -iE "[a-ZA-Z]+\.$id" | grep -i $node | awk '{print $2}' | tr -d ' ')
	if [ "$ip" == "" ]; then
		echo -e "${RED}Error, the kit ${GRE}$node${RED} with id ${GRE}$id${RED} was not found.${RST}"
		exit 1
	fi
	key=$(cat $DB | grep -iEw "$ip" | awk '{print $4}' | tr -d ' ')
	message="$node.$id"
	extended="($ip)"

	if [ "$ip" == "" ] || [ "$key" == "" ]; then
		echo -e "${RED}Error, combination was not found, maybe you should update the db.$RST"
		exit 1
	fi
fi

if [ "$node" != "" ]; then
	logname="$node.$id"
else
	logname="$ip"
fi
key="$key_path$key.pem"

echo -e "Connecting to $GRE$message$RST using $BLU$key$RST $extended"

if [[ ! -f $key ]]; then
	echo -e "${RED}Key doesn't exists$RST"
	exit 1
fi

logfile="${logpath}sshlog.$logname.$NOW.log"

echo -e "$RED══════════════════════════════════════════════════════════════════════════$RST"
#echo "ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=180 -i $key ubuntu@$ip"
if [ "$is_init" == 'true' ]; then
	username=$(id -u -n)
	username=${username^^} #convert to upper
	grep -q "$username" $init_config
	if [ $? != 0 ]; then
		echo "Writing username to $init_config file."
		sed -i "s/^owner='.*'$/owner='$username'/g" $DB
	fi
	ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=180 -i $key ubuntu@$ip < $init_config
	echo -e "Reconnecting..."
fi
ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=180 -i $key ubuntu@$ip | tee -a $logfile
echo -e "$RED══════════════════════════════════════════════════════════════════════════$RST"
echo -e "${GRE}Log file: ${RST}$logfile"