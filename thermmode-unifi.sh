#!/bin/bash

##############################################################################
# Script Name	: thermmode-unifi
# Description	: Netatmo smart thermostat mode by connected UniFi clients
# Args          : <config_file>
# Author       	: Pieter Smets
# E-mail        : mail@pietersmets.be
##############################################################################

# exit when any command fails
set -e

#
# Some usefull links to documentation to create this script
#
# https://ubntwiki.com/products/software/unifi-controller/api
# https://gist.github.com/jcconnell/0ee6c9d5b25c572863e8ffa0a144e54b
# https://github.com/NickWaterton/Unifi-websocket-interface/blob/master/controller.py
# https://dev.netatmo.com/apidocumentation/energy

# Name of the script
SCRIPT=$( basename "$0" )

# Current version from git
VERSION="v0.3.1"


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
"Usage:  $SCRIPT <config_file>"
""
"Options:"
" -C, --config        Print a demo configuration file with all variables"
" -h, --help          Print help"
" -v, --verbose       Make the operation more talkative"
" -V, --version       Show version number and quit"
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


function version
{
#
# Message to display for version.
#
    printf "$VERSION\n"
    exit 0
}


function config 
{
#
# Message to display for version.
#
    local txt=(
"### thermmode-unifi configuration file."
""
"# The commented out lines are the configuration field and the default value used."
""
"###"
"### UniFi controller configuration"
"###"
""
"# UniFi controller address"
"UNIFI_ADDRESS = https://url_or_ip_of_your_controller"
""
"# UniFi sitename."
"# UNIFI_SITENAME = default"
""
"# UniFi controller username and password (preferably a local account with read-only rights)"
"UNIFI_USERNAME = ..."
"UNIFI_PASSWORD = ..."
""
"# List of client mac addresses (space separated)"
"UNIFI_CLIENTS = aa:aa:aa:aa:aa:aa bb:bb:bb:bb:bb:bb cc:cc:cc:cc:cc:cc"
""
"# Clients last seen threshold to set thermmode=away"
"# UNIFI_CLIENTS_OFFLINE_SECONDS = 600"
"# UNIFI_CLIENTS_IGNORE_SECONDS  = 1800"
""
"###"
"### Netatmo connect configuration"
"###"
""
"# A personal netatmo connect app registered to your username is required."
"# Create your app at https://dev.netatmo.com/apps."
"# The app is needed for authentication to obtain an Oauth2 Bearer token from"
"# your username and password."
""
"# Netatmo connect app technical parameters: client id and secret."
"NETATMO_CLIENT_ID = ..."
"NETATMO_CLIENT_SECRET = ..."
""
"# Netatmo username and password"
"NETATMO_USERNAME = ..."
"NETATMO_PASSWORD = ..."
""
"# Netamo home id (optional, defaults to the first of your homes)"
"# NETATMO_HOME_ID = ..."
    )

    printf "%s\n" "${txt[@]}"
    exit 0
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


function unifi_curl {
#
# UI curl alias with cookie
#
    /usr/bin/curl \
        --silent \
        --show-error \
        --cookie ${UNIFI_COOKIE} \
        --cookie-jar ${UNIFI_COOKIE} \
        --insecure \
        "$@"
}


function unifi_login {
#
# Login to the configured UI controller
#
    unifi_curl \
        --request POST \
        --header "Content-Type: application/json" \
        --data "{\"password\":\"$UNIFI_PASSWORD\",\"username\":\"$UNIFI_USERNAME\"}" \
        $UNIFI_ADDRESS:443/api/auth/login > /dev/null
}


function unifi_logout {
#
# Logout from the configured UI controller
#
   unifi_curl ${UNIFI_API}/logout > /dev/null
}


function unifi_active_clients {
#
# Get a list of all active clients on the site
#
    unifi_curl ${UNIFI_SITE_API}/stat/sta --compressed
}


function unifi_client {
#
# Get client details on the site
#
    local mac=$1
    unifi_curl ${UNIFI_SITE_API}/stat/user/${mac} --compressed
}


function netatmo_access_token {
#
# Netatmo Connect oauth2 access token
#
    response=$(/usr/bin/curl \
        --silent \
        --show-error \
        --header "accept: application/json" \
        --data grant_type=password \
        --data client_id=$NETATMO_CLIENT_ID \
        --data client_secret=$NETATMO_CLIENT_SECRET \
        --data username=$NETATMO_USERNAME \
        --data password=$NETATMO_PASSWORD \
        --data scope="read_thermostat write_thermostat" \
        https://api.netatmo.com/oauth2/token)
    if echo $response | grep error > /dev/null;
    then
        echo $response && exit 1
    fi   
    NETATMO_ACCESS_TOKEN="${response##*\"access_token\":\"}"
    NETATMO_ACCESS_TOKEN="${NETATMO_ACCESS_TOKEN%%\"*}"
}


function netatmo_curl {
#
# Netatmo Connect curl alias
#
    if [ "$NETATMO_ACCESS_TOKEN" == "" ];
    then
        echo "error: NETATMO_ACCESS_TOKEN is empty"
        exit 1
    fi
    response=$(/usr/bin/curl \
        --silent \
        --show-error \
        --header "accept: application/json" \
        --header "Authorization: Bearer $NETATMO_ACCESS_TOKEN" \
        "$@")
    echo $response
    if echo $response | grep error > /dev/null;
    then
        exit 1
    fi
}


function netatmo_homesdata {
#
# Get the homesdata from Netatmo Connect
#
    netatmo_curl \
        --request GET \
        ${NETATMO_API}/homesdata
}


function netatmo_gethomeid {
#
# Get the first home id from Netatmo Connect
#
    local resp="$(netatmo_homesdata || echo "error")"
    if ! echo $resp | grep error > /dev/null;
    then
        resp="${resp##*\"homes\":[\{\"id\":\"}"
        resp="${resp%%\"*}"
    fi
    echo $resp
}


function netatmo_homestatus {
#
# Get the homestatus from Netatmo energy
#
    netatmo_curl \
        --request GET \
        --data home_id=$NETATMO_HOME_ID \
        ${NETATMO_API}/homestatus
}


function netatmo_isthermmode {
#
# Verify if the current thermostat mode is schedule|away|hg
#
    case "$1" in
        schedule|away|hg)
        ;;
        *)
        echo "thermmode status should be any of 'schedule|away|hg'!"
        exit 1
        ;;
    esac
    netatmo_homestatus | grep "\"therm_setpoint_mode\":\"$1\""
}


function netatmo_getthermmode {
#
# Get the thermostat mode
#
    local resp="$(netatmo_homestatus || echo "error")"
    if ! echo $resp | grep error > /dev/null;
    then
        resp="${resp##*\"therm_setpoint_mode\":\"}"
        resp="${resp%%\"*}"
    fi
    echo $resp
}


function netatmo_setthermmode {
#
# Set the thermostat mode
#
    case "$1" in
        schedule|away|hg)
        ;;
        *)
        echo "thermmode status should be any of 'schedule|away|hg'!"
        exit 1
        ;;
    esac
    netatmo_curl \
        --request POST \
        --data home_id=$NETATMO_HOME_ID \
        --data mode=$1 \
        ${NETATMO_API}/setthermmode
}


function verbose {
#
# Talkative mode: echo only when --verbose
#
    if [ $DO_VERB -eq 1 ];
    then
        echo "$@"
    fi
}


#-------------------------------------------------------------------------------
#
# Parse arguments and configuration file
#
#-------------------------------------------------------------------------------

#
# Parse options
#
DO_VERB=0
while (( $# ));
do
    case "$1" in
        -c|--config) config
        ;;
        -h|--help) usage
        ;;
        -v|--verbose) DO_VERB=1
        ;;
        -V|--version) version
        ;;
        *) break
    esac
    shift
done

#
# Check arguments
#
if (($# > 1 ));
then
    badUsage "Illegal number of arguments"
fi

#
# Set UNIFI and NETATMO variables
#

# Initialize defaults
UNIFI_SITENAME="${UNIFI_SITENAME:-default}"
UNIFI_CLIENTS_OFFLINE_SECONDS=${UNIFI_CLIENTS_OFFLINE_SECONDS:-600}
UNIFI_CLIENTS_IGNORE_SECONDS=${UNIFI_CLIENTS_IGNORE_SECONDS:-1800}

# Parse config file
if (($# == 1 ));
then
    parse_config $1 \
        UNIFI_ADDRESS UNIFI_USERNAME UNIFI_PASSWORD UNIFI_SITENAME \
        UNIFI_CLIENTS UNIFI_CLIENTS_OFFLINE_SECONDS UNIFI_CLIENTS_IGNORE_SECONDS \
        NETATMO_CLIENT_ID NETATMO_CLIENT_SECRET NETATMO_USERNAME NETATMO_PASSWORD \
        NETATMO_HOME_ID
fi

# Check if mandatory variables are set
check_config UNIFI_ADDRESS UNIFI_USERNAME UNIFI_PASSWORD UNIFI_SITENAME UNIFI_CLIENTS
check_config NETATMO_CLIENT_ID NETATMO_CLIENT_SECRET NETATMO_USERNAME NETATMO_PASSWORD

# Construct derived variables
UNIFI_COOKIE=$(mktemp)
UNIFI_API="${UNIFI_ADDRESS}/proxy/network/api"
UNIFI_SITE_API="${UNIFI_API}/s/${UNIFI_SITENAME}"
NETATMO_API="https://api.netatmo.com/api"
NETATMO_ACCESS_TOKEN=""


#-------------------------------------------------------------------------------
#
# Netatmo Connect access token and home id
#
#-------------------------------------------------------------------------------

netatmo_access_token

if [ "$NETATMO_HOME_ID" == "" ];
then
    NETATMO_HOME_ID=$(netatmo_gethomeid)
fi


#-------------------------------------------------------------------------------
#
# Client verification
#
#-------------------------------------------------------------------------------

now=$(date +%s)

ignore=1
offline=1

unifi_login

for CLIENT in $UNIFI_CLIENTS;
do
    # Get client data
    CLIENT_DATA="$(unifi_client $CLIENT)"

    # Check if client is configured
    if ! echo $CLIENT_DATA | grep "\"meta\":{\"rc\":\"ok\"}" >/dev/null 2>&1;
    then
        verbose "$CLIENT is not a configured client."
        continue
    fi
    # echo $CLIENT_DATA

    # Parse client data
    hostname="${CLIENT_DATA##*\"hostname\":\"}"
    hostname="${hostname%%\",*}"

    last_seen="${CLIENT_DATA##*\"last_seen\":}"
    last_seen="${last_seen%%,*}"

    elapsed=$(($now - $last_seen))
    # echo "$now $last_seen"

    verbose "$CLIENT $hostname last seen $elapsed seconds ago."

    if [ $elapsed -lt $UNIFI_CLIENTS_OFFLINE_SECONDS ];
    then
        offline=0
        ignore=0
    elif [ $elapsed -lt $UNIFI_CLIENTS_IGNORE_SECONDS ];
    then
        ignore=0
    fi
done

unifi_logout

if [ $offline -eq 0 ] && [ $ignore -eq 0 ];
then
    unifi_mode='active'
elif [ $offline -eq 1 ] && [ $ignore -eq 0];
then
    unifi_mode='offline'
else
    unifi_mode='ignore'
fi


touch $HOME/.thermmode-unifi.mode

previous_mode=$(cat $HOME/.thermmode-unifi.mode)

if [ "$previous_mode" == "$unifi_mode" ];
then
    verbose "** No change in thermostat mode **"
    exit 0
fi

echo "$unifi_mode" > $HOME/.thermmode-unifi.mode


#-------------------------------------------------------------------------------
#
# Set thermostat mode
#
#-------------------------------------------------------------------------------

resp=''

if [ "$unifi_mode" != "ignore" ];
then

    therm_mode="$(netatmo_getthermmode || echo "error")"

    if echo $therm_mode | grep error > /dev/null;
    then
        echo "** $therm_mode ** "
        exit 1
    elif [ "$therm_mode" == "hg" ];
    then
        verbose "** Thermostat is in frost guard mode ** "
        exit 0
    else
        verbose "** Thermostat mode = $therm_mode **"
    fi

    if [ "$unifi_mode" == "offline" ] && [ "$therm_mode" == "schedule" ];
    then
        echo "** Set thermostat mode to away **"
        resp=$(netatmo_setthermmode 'away')
    elif [ "$unifi_mode" == "active" ] && [ "$therm_mode" == "away" ];
    then
        echo "** Set thermostat mode to schedule **"
        resp=$(netatmo_setthermmode 'schedule')
    else
        verbose "** No need to change the thermostat mode **"
    fi

    if echo $resp | grep error > /dev/null;
    then
        echo $resp
        exit 1
    fi
fi

exit 0
