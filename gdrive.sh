#!/bin/bash
# title          : grive.sh
# description    : A sandbox to play a little bit with google drive api
# author		 : Korby (https://github.com/korby)
# date 	         : feb. 2018 

client_id=""
client_secret=""
tokens_path="/tmp/"$client_id
google_url_console="https://console.developers.google.com/apis/"
google_url_get_code="https://accounts.google.com/o/oauth2/auth?scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive&redirect_uri=urn:ietf:wg:oauth:2.0:oob&response_type=code&client_id=$client_id"
google_url_get_tokens="https://accounts.google.com/o/oauth2/token"

if [ "$(uname)" == "Darwin" ]; then
        sed_compat=" \"\" "
else
        sed_compat=""
fi

if [ "$client_id" == "" ]; then echo "Need client_id, you can get it here: "; echo $google_url_console; exit 1; fi
if [ "$client_secret" == "" ]; then echo "Need client_secret, you can get it here: "; echo $google_url_console; exit 1; fi
if [ ! -f $tokens_path ]; then
	echo "Need a code to get token, please get it here: "
	echo $google_url_get_code
    read -p "Type the code:" code
	json_back=`curl -H 'Content-Type: application/x-www-form-urlencoded' -d 'code=$code&client_id=$client_id&client_secret=$client_secret&redirect_uri=urn:ietf:wg:oauth:2.0:oob&grant_type=authorization_code' $google_url_get_tokens`
    refresh_token=`echo $json_back | grep "refresh_token" |cut -d ":" -f2 | sed "s/.$//" | sed "s/^.//" | sed 's/"//g'`
    if [ "$refresh_token" == "" ]; then
    	echo "Failure during token request, here the response:"
    	echo $json_back
    	exit 1
    fi
    echo "$refresh_token" > $tokens_path;
fi

function get_access_token () {
	access_token=""
	# if token is less than one hour aged
    if [ "$(find $tokens_path -mmin +55)" == "" ]; then
    	access_token=`cat $tokens_path | cut -d ':' -f2`
    fi 
	if [ "$access_token" == "" ]; then
		echo "Asking for a fresh token";
		refresh_token=`cat $tokens_path | cut -d ':' -f1`;
		json_back=`curl -d "client_id=$client_id&client_secret=$client_secret&refresh_token=$refresh_token&grant_type=refresh_token" $google_url_get_tokens`;
		access_token=`echo "$json_back" | grep "access_token" |cut -d ":" -f2 | sed "s/.$//" | sed "s/^.//" | sed 's/"//g'`
		echo "$json_back" > /tmp/test.txt
		sed -i $sed_compat"s/:.*$/:$access_token/g" $tokens_path
	fi
	
    echo $access_token;
}

function upload () {
	access_token=$1
	filepath=$2
	filesize=`stat -f%z $filepath`
	mimetype=`file --mime-type $filepath | cut -d":" -f2 | sed "s/^ //"`
    title=`basename "$filepath"`


	postData="{\"mimeType\": \"$mimetype\",\"name\": \"$title\",\"parents\": [{\"kind\": \"drive#file\",\"id\": \"root\"}]}"
	postDataSize=$(echo $postData | wc -c)
	ref=`curl --silent \
				-X POST \
				-H "Host: www.googleapis.com" \
				-H "Authorization: Bearer $access_token" \
				-H "Content-Type: application/json; charset=UTF-8" \
				-H "X-Upload-Content-Type: $mimetype" \
				-H "X-Upload-Content-Length: $filesize" \
				-d "$postData" \
				"https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable" \
				--dump-header - `

	refloc=`echo "$ref" | grep location | sed "s/location: //" | tr -d '\r\n'`
	curl -X PUT --dump-header - -H "Authorization: Bearer "$access_token -H "Content-Type: "$mimetype -H "Content-Length: "$filesize -H "Slug: "$title --upload-file $filepath $refloc

}
access_token=`get_access_token`;

while getopts "lu:" opt; do
    case "$opt" in
    l)
        echo "Listing drives root files...";
		curl -H "GData-Version: 3.0" -H "Authorization: Bearer $access_token" https://www.googleapis.com/drive/v2/files
        exit 0
        ;;
    u)  
		echo `upload $access_token $OPTARG`
        ;;
    \?)
      exit 1
      ;;
    esac
done

exit 0;