#!/bin/bash

##############################################################################
# Script Name	: thermmode-uiclient
# Description	: Netatmo smart thermostat mode by connected UniFi clients
# Args          : <config_file>
# Author       	: Pieter Smets
# E-mail        : mail@pietersmets.be
##############################################################################

#
# Some usefull links to documentation to create this script
#
# https://ubntwiki.com/products/software/unifi-controller/api
# https://gist.github.com/jcconnell/0ee6c9d5b25c572863e8ffa0a144e54b
# https://github.com/NickWaterton/Unifi-websocket-interface/blob/master/controller.py
# https://dev.netatmo.com/apidocumentation/energy

# Name of the script
SCRIPT=$( basename "$0" )


#-------------------------------------------------------------------------------
#
# Function definitions
#
#-------------------------------------------------------------------------------

function usage {
#
# Message to display for usage and help
#
    local txt=(
"UniFi client montoring for geolocation-like functionality of the Netatmo Smart Thermostat."
""
"UniFi clients of interest are monitored to automatically set the thermostat mode."
"The thermostat is set to 'mode=away' when all listed clients are disconnected longer "
"than the threshold UI_CLIENT_OFFLINE_SECONDS (defaults to 900s)."
"As soon as any of the listed clients reconnects the thermostat is set to 'mode=schedule'."
""
"Clients of interest are listed by their mac address (formatted 12:34:56:78:90:ab) and"
"corresponding connection details are retrieved from the UniFi's controller."
""
"When the thermostat mode is set to frost guard ('mode=hg') client monitoring is disabled."
""
"Usage:  $SCRIPT <config_file>"
""
"Required config/environment variables:"
"  UI_ADDRESS UI_USERNAME UI_PASSWORD UI_SITENAME UI_CLIENTS UI_CLIENT_OFFLINE_SECONDS"
"  NC_USER_ID NC_HOME_ID NC_USER_TOKEN"
    )

    printf "%s\n" "${txt[@]}"
    exit 0
}


function badUsage {
#
# Message to display when bad usage
#
    local message="$1"
    local txt=(
"For an overview of the command, execute:"
"$SCRIPT --help"
    )

    [[ $message ]] && printf "$message\n"

    printf "%s\n" "${txt[@]}"
    exit -1
}


function parse_config { # parse_config file.cfg var_name1 var_name2
#
# This function will read key=value pairs from a configfile.
#
# After invoking 'readconfig somefile.cfg my_var',
# you can 'echo "$my_var"' in your script.
#
# ONLY those keys you give as args to the function will be evaluated.
# This is a safeguard against unexpected items in the file.
#
# ref: https://stackoverflow.com/a/20815951
#
# The config-file could look like this:
#-------------------------------------------------------------------------------
# This is my config-file
# ----------------------
# Everything that is not a key=value pair will be ignored. Including this line.
# DO NOT use comments after a key-value pair!
# They will be assigend to your key otherwise.
#
# singlequotes = 'are supported'
# doublequotes = "are supported"
# but          = they are optional
#
# this=works
#
# # key = value this will be ignored
#
#-------------------------------------------------------------------------------
    shopt -s extglob # needed the "one of these"-match below
    local configfile="${1?No configuration file given}"
    local keylist="${@:2}"    # positional parameters 2 and following
    local lhs rhs

    if [[ ! -f "$configfile" ]];
    then
        >&2 echo "\"$configfile\" is not a file!"
        exit 1
    fi
    if [[ ! -r "$configfile" ]];
    then
        >&2 echo "\"$configfile\" is not readable!"
        exit 1
    fi

    keylist="${keylist// /|}" # this will generate a regex 'one of these'

    # lhs : "left hand side" : Everything left of the '='
    # rhs : "right hand side": Everything right of the '='
    #
    # "lhs" will hold the name of the key you want to read.
    # The value of "rhs" will be assigned to that key.
    while IFS='= ' read -r lhs rhs
    do
        # IF lhs in keylist
        # AND rhs not empty
        if [[ "$lhs" =~ ^($keylist)$ ]] && [[ -n $rhs ]];
        then
            rhs="${rhs%\"*}"     # Del opening string quotes
            rhs="${rhs#\"*}"     # Del closing string quotes
            rhs="${rhs%\'*}"     # Del opening string quotes
            rhs="${rhs#\'*}"     # Del closing string quotes
            eval $lhs=\"$rhs\"   # The magic happens here
        fi
    # tr used as a safeguard against dos line endings
    done < $configfile
    # done <<< $( tr -d '\r' < $configfile )

    shopt -u extglob # Switching it back off after use
}


function check_config { # check_config var1 var2 ...
#
# Check if the provided variables are set
#
    local var
    for var in "${@}";
    do
        if [ -z "${!var}" ];
        then
            echo "Error: variable $var is empty!"
            exit 1
        fi
    done
}


function ui_curl {
#
# UI curl alias with cookie
#
    /usr/bin/curl \
        --silent \
        --show-error \
        --cookie ${UI_COOKIE} \
        --cookie-jar ${UI_COOKIE} \
        --insecure \
        "$@"
}


function ui_login {
#
# Login to the configured UI controller
#
    ui_curl \
        --request POST \
        --header "Content-Type: application/json" \
        --data "{\"password\":\"$UI_PASSWORD\",\"username\":\"$UI_USERNAME\"}" \
        $UI_ADDRESS:443/api/auth/login > /dev/null
}


function ui_logout {
#
# Logout from the configured UI controller
#
   ui_curl ${UI_API}/logout > /dev/null
}


function ui_active_clients {
#
# Get a list of all active clients on the site
#
    ui_curl ${UI_SITE_API}/stat/sta --compressed
}


function ui_client {
#
# Get client details on the site
#
    local mac=$1
    ui_curl ${UI_SITE_API}/stat/user/${mac} --compressed
}


function nc_curl {
#
# Netatmo Connect curl alias
#
    /usr/bin/curl \
        --silent \
        --show-error \
        --header "accept: application/json" \
        --header "Authorization: Bearer ${NC_USER_ID}|${NC_USER_TOKEN}" \
        "$@"
}


function nc_homestatus {
#
# Get the thermmode from netatmo connect
#
    nc_curl \
        --request GET \
        --data home_id=${NC_HOME_ID} \
        ${NC_API}/homestatus
}


function nc_isthermmode {
#
# Verify the current thermmode status
#
    case "$1" in
        schedule|status|hg)
        ;;
        *)
        echo "thermmode status should be any of 'schedule|away|hg'!"
        exit 1
        ;;
    esac
    nc_homestatus | grep "\"therm_setpoint_mode\":\"$1\""
}


function nc_getthermmode {
#
# Echo the current thermmode status
#
    local mode="$(nc_homestatus)"
    mode="${mode##*\"therm_setpoint_mode\":\"}"
    mode="${mode%%\"*}"
    echo $mode
}


function nc_setthermmode {
#
# Set the thermostat mode
#
    case "$1" in
        schedule|status|hg)
        ;;
        *)
        echo "thermmode status should be any of 'schedule|away|hg'!"
        exit 1
        ;;
    esac
    curl \
        --request POST \
        --data home_id=${NC_HOME_ID} \
        --data mode=${mode} \
        ${NC_API}/setthermmode
}


function now {
#
# Get current time in epoch seconds
#
    date +%s
}


#-------------------------------------------------------------------------------
#
# Parse configuration file
#
#-------------------------------------------------------------------------------

#
# Check input arguments
#
if (($# > 1 ));
then
    badUsage "Illegal number of arguments"
fi

case "$1" in
    help|--help|-h) usage
    ;;
esac


#
# Set UI and NC variables
#

# Initialize defaults
UI_SITENAME="${UI_SITENAME:-default}"
UI_CLIENT_OFFLINE_SECONDS=${UI_CLIENT_OFFLINE_SECONDS:-900}

# Parse config file
if (($# == 1 ));
then
    parse_config $1 \
        UI_ADDRESS UI_USERNAME UI_PASSWORD UI_SITENAME UI_CLIENTS UI_CLIENT_OFFLINE_SECONDS \
        NC_USER_ID NC_HOME_ID NC_USER_TOKEN
fi

# Check if mandatory variables are set
check_config UI_ADDRESS UI_USERNAME UI_PASSWORD UI_SITENAME UI_CLIENTS
check_config NC_USER_ID NC_HOME_ID NC_USER_TOKEN

# Construct derived variables
UI_COOKIE=$(mktemp)
UI_API="${UI_ADDRESS}/proxy/network/api"
UI_SITE_API="${UI_API}/s/${UI_SITENAME}"
NC_API="https://api.netatmo.com/api"


#-------------------------------------------------------------------------------
#
# Verify frost guard
#
#-------------------------------------------------------------------------------

mode="$(nc_getthermmode)"

if [ "$mode" == "hg" ];
then
    echo "** Thermostat is in frost guard mode ** "
    exit 0
fi


#-------------------------------------------------------------------------------
#
# Client verification
#
#-------------------------------------------------------------------------------

now=$(now)
off=true

ui_login

for CLIENT in $UI_CLIENTS;
do
    # Get client data
    CLIENT_DATA="$(ui_client $CLIENT)"

    # Check if client is configured
    if ! echo $CLIENT_DATA | grep "\"meta\":{\"rc\":\"ok\"}" >/dev/null 2>&1;
    then
        echo "$CLIENT is not a configured client."
        continue
    fi

    # Parse client data
    hostname="${CLIENT_DATA##*\"hostname\":\"}"
    hostname="${hostname%%\",*}"

    last_seen="${CLIENT_DATA##*\"last_seen\":}"
    last_seen="${last_seen%%,*}"

    elapsed=$(($now - $last_seen))
    echo "$CLIENT $hostname last seen $elapsed seconds ago."

    if [ $elapsed -gt $UI_CLIENT_OFFLINE_SECONDS ];
    then
        off=false
    fi
done

ui_logout


#-------------------------------------------------------------------------------
#
# Set thermostat mode
#
#-------------------------------------------------------------------------------

if [ "$off" == "true" ] & [ "$mode" == "schedule" ];
then
    echo "** Set thermostat mode to away **"
    nc_setthermmode 'away'
elif [ "$off" == "false" ] & [ "$mode" == "away" ];
then
    echo "** Set thermostat mode to schedule **"
    nc_setthermmode 'schedule'
else
    echo "** No need to change the thermostat mode **"
fi


exit 0
