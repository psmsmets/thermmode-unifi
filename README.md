# thermmode-unifi
Enable geolocation-like functionality of the Netatmo Smart Thermostat by monitoring UniFi clients.

UniFi clients of interest are monitored to automatically set the thermostat mode.
The thermostat is set to `away` when all listed clients are disconnected longer
than the threshold.
As soon as any of the listed clients reconnects the thermostat is set to `schedule`.

Clients of interest are listed by their mac address (formatted 12:34:56:78:90:ab) and
corresponding connection details are retrieved from the UniFi's controller.

When the thermostat mode is set to frost guard client monitoring and changing the thermostat mode are disabled.


## Preparation
Configure the UniFi controller and Netatmo Connect accordingly. 
All related variables should either be defined as shell (environment) variables or provided in a configuration file.

### UniFi controller
Create a local user for the UniFi controller with read-only access.

1. Add user
1. Set role to `Limited Admin`
1. Set account type to `Local Access Only`
1. Complete the first name, last name, local username and local password fields. All other fields can be left blank.
1. In application permission, set the Unifi Network  to `View Only`. All other applications can either be `View Only` or `None`.

Add the UniFi Controller variables to your shell or the configuration file.

### Netatmo Connect

Create an app at <https://dev.netatmo.com/apps/> to obtain the API `client ID` and `client secret` (App Technical Parameters) and a non-expiring token (Token generator with scopes `read_thermostat` and `write_thermostat`). 
Authentication is obtained via Oauth2 Bearer (<https://dev.netatmo.com/apidocumentation/oauth>).

Add the Netatmo Connect variables to your shell or the configuration file.

If you don't know your home id the field can be left blank. The script will get the first of your homes on Netatmo.

## Usage
```
Usage:  thermmode-unifi.sh <config_file>

Options:
 -C, --config        Print a demo configuration file with all variables
 -h, --help          Print help
 -m, --mode          Print the previous unifi mode"
 -f, --force         Ignore the stored unifi mode and force syncing the thermostat
 -v, --verbose       Make the operation more talkative
 -V, --version       Show version number and quit
```

Complete all of the following variables either in a configuration file or as environment variables
```
### thermmode-unifi configuration file.

# The commented out lines are the configuration field and the default value used.

###
### UniFi controller configuration
###

# UniFi controller address
UNIFI_ADDRESS = "https://url_or_ip_of_your_controller"

# UniFi sitename.
# UNIFI_SITENAME = "default"

# UniFi controller username and password (preferably a local account with read-only rights)
UNIFI_USERNAME = ...
UNIFI_PASSWORD = ...

# List of client mac addresses (space separated)
UNIFI_CLIENTS = aa:aa:aa:aa:aa:aa bb:bb:bb:bb:bb:bb cc:cc:cc:cc:cc:cc

# Clients last seen threshold to set thermmode=away
# UNIFI_CLIENTS_OFFLINE_SECONDS = 600
# UNIFI_CLIENTS_IGNORE_SECONDS  = 1800

###
### Netatmo connect configuration
###

# A personal netatmo connect app registered to your username is required.
# Create your app at https://dev.netatmo.com/apps.
# The app is needed for authentication to obtain an Oauth2 Bearer token from
# your username and password.

# Netatmo connect app technical parameters: client id and secret.
NETATMO_CLIENT_ID = ...
NETATMO_CLIENT_SECRET = ...

# Netatmo access token.
NETATMO_ACCESS_TOKEN = ...
NETATMO_REFRESH_TOKEN = ...

# Netamo home id (optional, defaults to the first of your homes)
# NETATMO_HOME_ID = ...
```

Missing variables from the configuration file are assumed to be set in your shell (locally or as enviroment variables).


## Automatic trigger via Crontab
Trigger the Netatmo thermostat mode update every two minute using crontab (`sudo crontab -e`) and log the output in syslog.
```
*/2 * * * * thermmode-unifi.sh my-home.conf 2>&1 | /usr/bin/logger -t netatmo 
```
Make sure that the absolute path to both the script and configuration file are set.

Scan the syslog output via `journalctl`
```
journalctl -t netatmo --since today
``` 
