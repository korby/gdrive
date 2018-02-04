#!/bin/bash

# A simple cURL OAuth2 authenticator
# depends on Python's built-in json module to prettify output
#
# Usage:
#	./google-oauth2.sh create - authenticates a user
#	./google-oauth2.sh refresh <token> - gets a new token
#
# Set CLIENT_ID and CLIENT_SECRET and SCOPE

CLIENT_ID="640975269387-bt7i5n5b6vrj83ahcdr9refmus4aqghj.apps.googleusercontent.com"
CLIENT_SECRET="-U99gF5HAe3gbYhWVWB0Xvh1"
SCOPE=${SCOPE:-"https://docs.google.com/feeds"}


#curl --silent "https://www.googleapis.com/oauth2/v4/token" --data "client_id=$CLIENT_ID&scope=$SCOPE"

#https://accounts.google.com/o/oauth2/auth?scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive&redirect_uri=urn:ietf:wg:oauth:2.0:oob&response_type=code&client_id=640975269387-bt7i5n5b6vrj83ahcdr9refmus4aqghj.apps.googleusercontent.com

#4/uWNr71Dmb4dGFexiFQGtdyUfq3G6XJlniMdbBI8bcXg

echo "curl -H 'Content-Type: application/x-www-form-urlencoded' -d 'code=4/eq-t1dGCj_BBDvREHCcOGaZf9LVeXPwC9I8NQgHl3JY&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&redirect_uri=urn:ietf:wg:oauth:2.0:oob&grant_type=authorization_code' https://accounts.google.com/o/oauth2/token"

exit 0
set -e

if [ "$1" == "create" ]; then
	RESPONSE=`curl --silent "https://accounts.google.com/o/oauth2/device/code" --data "client_id=$CLIENT_ID&scope=$SCOPE"`
	DEVICE_CODE=`echo "$RESPONSE" | python -mjson.tool | grep -oP 'device_code"\s*:\s*"\K(.*)"' | sed 's/"//'`
	USER_CODE=`echo "$RESPONSE" | python -mjson.tool | grep -oP 'user_code"\s*:\s*"\K(.*)"' | sed 's/"//'`
	URL=`echo "$RESPONSE" | python -mjson.tool | grep -oP 'verification_url"\s*:\s*"\K(.*)"' | sed 's/"//'`

	echo -n "Go to $URL and enter $USER_CODE to grant access to this application. Hit enter when done..."
	read

	RESPONSE=`curl --silent "https://accounts.google.com/o/oauth2/token" --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&code=$DEVICE_CODE&grant_type=http://oauth.net/grant_type/device/1.0"`

	ACCESS_TOKEN=`echo "$RESPONSE" | python -mjson.tool | grep -oP 'access_token"\s*:\s*"\K(.*)"' | sed 's/"//'`
	REFRESH_TOKEN=`echo "$RESPONSE" | python -mjson.tool | grep -oP 'refresh_token"\s*:\s*"\K(.*)"' | sed 's/"//'`

	echo "Access Token: $ACCESS_TOKEN"
	echo "Refresh Token: $REFRESH_TOKEN"
elif [ "$1" == "refresh" ]; then
	REFRESH_TOKEN=$2
	RESPONSE=`curl --silent "https://accounts.google.com/o/oauth2/token" --data "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN&grant_type=refresh_token"`

	ACCESS_TOKEN=`echo $RESPONSE | python -mjson.tool | grep -oP 'access_token"\s*:\s*"\K(.*)"' | sed 's/"//'`
	
	echo "Access Token: $ACCESS_TOKEN"
fi
