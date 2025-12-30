#!/bin/bash
# title          : grive.sh
# description    : A sandbox to play a little bit with google drive api
# author		 : Korby (https://github.com/korby)
# date 	         : feb. 2018

access_token=""
# If stdin is not empty, get token from it
if [ ! -t 0 ];
then
  while read line
  do
    access_token=$line
  done < /dev/stdin
fi

client_id="$(cat client_id.txt 2>/dev/null)"
client_secret="$(cat client_secret.txt 2>/dev/null)"
tokens_path=$client_id  
google_url_console="https://console.developers.google.com/apis/"
redirect_uri="http://localhost:8099"
google_url_get_code="https://accounts.google.com/o/oauth2/auth?scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive&redirect_uri=$redirect_uri&response_type=code&client_id=$client_id&access_type=offline&prompt=consent"
google_url_get_tokens="https://accounts.google.com/o/oauth2/token"

# Load parent_dir.env if it exists (must be loaded before upload function uses it)
if [ -f "./parent_dir.env" ]; then 
  . ./parent_dir.env
fi

if [ "$client_id" == "" ]; then echo "Need client_id, you can get it here: "; echo "$google_url_console/credentials"; exit 1; fi
if [ "$client_secret" == "" ]; then echo "Need client_secret, you can get it here: "; echo "$google_url_console/credentials"; exit 1; fi
if [ ! -f $tokens_path ] && [ "$access_token" = "" ]; then
	echo "Please visit this URL to authorize:"
	echo ""
	echo $google_url_get_code
	echo ""
	echo "After authorization, you will be redirected to: $redirect_uri"
	echo "Copy the 'code' parameter from the URL in your browser's address bar."
	echo "Example: if the URL is http://localhost:8099/?code=4/0A... then copy '4/0A...'"
	echo ""
	
	# Try to open the URL automatically
	if command -v open >/dev/null 2>&1; then
		open "$google_url_get_code" 2>/dev/null
	elif command -v xdg-open >/dev/null 2>&1; then
		xdg-open "$google_url_get_code" 2>/dev/null
	fi
	
	read -p "Enter the authorization code from the URL: " code
	
	if [ -z "$code" ]; then
		echo "Error: No code provided"
		exit 1
	fi
	
	echo "Getting tokens..."
	json_back=`curl -H 'Content-Type: application/x-www-form-urlencoded' -d "code=$code&client_id=$client_id&client_secret=$client_secret&redirect_uri=$redirect_uri&grant_type=authorization_code" $google_url_get_tokens`

    refresh_token=`echo "$json_back" | grep "refresh_token" |cut -d ":" -f2 | sed "s/.$//" | sed "s/^.//" | sed 's/"//g'`
    if [ "$refresh_token" == "" ]; then
    	echo "Failure during token request, here the response:"
    	echo $json_back
    	exit 1
    fi
    echo "$refresh_token:" > $tokens_path;
fi

function get_access_token () {
  if [ "$access_token" != "" ]; then echo $(echo $access_token | cut -d ':' -f2); return 0; fi
	# if token is less than one hour aged
    if [ "$(find $tokens_path -mmin +55)" == "" ]; then
    	access_token=`cat $tokens_path | cut -d ':' -f2`
    fi
	if [ "$access_token" == "" ]; then
		refresh_token=`cat $tokens_path | cut -d ':' -f1`;
		json_back=`curl -d "client_id=$client_id&client_secret=$client_secret&refresh_token=$refresh_token&grant_type=refresh_token" $google_url_get_tokens`;
		access_token=`echo "$json_back" | grep "access_token" |cut -d ":" -f2 | sed "s/.$//" | sed "s/^.//" | sed 's/"//g'`
    if [ "$(uname)" == "Darwin" ]; then
            sed -i "" "s/:.*$/:$access_token/g" $tokens_path
    else
            sed -i "s/:.*$/:$access_token/g" $tokens_path
    fi

	fi

    echo $access_token;
}

function upload () {
	access_token=$1
	filepath=$2

	filesize=`ls -nl $filepath | awk '{print $5}'`
	mimetype=`file --mime-type $filepath | cut -d":" -f2 | sed "s/^ //"`
    title=`basename "$filepath"`

  # If parent_dir_id is set, upload go in
  if [ "$parent_dir_id" != "" ]; then
	  postData="{\"parents\": [\"$parent_dir_id\"],\"mimeType\": \"$mimetype\",\"name\": \"$title\"}"
  else
  # upload go tho the gdrive root dir
    postData="{\"mimeType\": \"$mimetype\",\"name\": \"$title\",\"parents\": [{\"kind\": \"drive#file\",\"id\": \"root\"}]}"
  fi
  
  # Debug: show parent_dir_id if set
  if [ "$parent_dir_id" != "" ]; then
    echo "Uploading to parent directory: $parent_dir_id" >&2
  else
    echo "Uploading to root directory" >&2
  fi
  
 
	postDataSize=$(echo $postData | wc -c)
	ref=`curl --silent \
				-X POST \
				-H "Host: www.googleapis.com" \
				-H "Authorization: Bearer $access_token" \
				-H "Content-Type: application/json; charset=UTF-8" \
				-H "X-Upload-Content-Type: $mimetype" \
				-H "X-Upload-Content-Length: $filesize" \
				-d "$postData" \
				"https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true" \
				--dump-header - `

	# Check for errors in the response
	if echo "$ref" | grep -q '"error"'; then
		error_msg=$(echo "$ref" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
		echo "Error during upload initialization: ${error_msg:-Unknown error}" >&2
		echo "Response: $ref" >&2
		exit 1
	fi

	refloc=`echo "$ref" | grep -i location | perl -p -e 's/location: //gi' | tr -d '\r\n'`
	if [ -z "$refloc" ]; then
		echo "Error: No upload location received from server" >&2
		echo "Response: $ref" >&2
		exit 1
	fi
	echo $refloc > ./gdrive.log
	curl -X PUT --dump-header - -H "Authorization: Bearer "$access_token -H "Content-Type: "$mimetype -H "Content-Length: "$filesize --upload-file $filepath $refloc

}
access_token=`get_access_token`;

while getopts "lu:" opt; do
    case "$opt" in
    l)
        if [ "$parent_dir_id" != "" ]; then
            # Get parent directory name - try with supportsAllDrives parameter for shared drives
            parent_info=$(curl -s -H "Authorization: Bearer $access_token" "https://www.googleapis.com/drive/v3/files/$parent_dir_id?fields=name&supportsAllDrives=true")
            
            # Try to parse JSON - use jq if available, otherwise use sed/grep
            if command -v jq >/dev/null 2>&1; then
                parent_name=$(echo "$parent_info" | jq -r '.name // empty' 2>/dev/null)
            else
                # Fallback: extract name from JSON manually
                parent_name=$(echo "$parent_info" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
            fi
            
            # Check for API errors
            if echo "$parent_info" | grep -q '"error"'; then
                error_code=$(echo "$parent_info" | grep -o '"code":[^,}]*' | cut -d':' -f2 | tr -d ' ')
                error_msg=$(echo "$parent_info" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
                
                if [ "$error_code" = "404" ]; then
                    echo "Error: Directory not found or not accessible."
                    echo ""
                    echo "Possible causes:"
                    echo "  1. The directory ID is incorrect"
                    echo "  2. The OAuth token was generated with a different Google account"
                    echo "  3. The directory is in a Shared Drive and requires special permissions"
                    echo "  4. You need to regenerate your OAuth token"
                    echo ""
                    echo "To fix: Delete the token file and run './gdrive.sh -l' again to re-authenticate:"
                    echo "  rm $tokens_path"
                    echo "  ./gdrive.sh -l"
                else
                    echo "Error accessing parent directory: ${error_msg:-Unknown error (code: $error_code)}"
                fi
                echo ""
                echo "Full API response:"
                echo "$parent_info"
                exit 1
            fi
            
            if [ -z "$parent_name" ]; then
                parent_name="(Unknown - ID: $parent_dir_id)"
            fi
            
            echo "Parent directory: $parent_name"
            echo ""
            echo "Files in $parent_name:"
            echo "----------------------------------------"
            
            # List files in the parent directory - include supportsAllDrives for shared drives
            # URL encode the query parameter properly
            query_param="'$parent_dir_id' in parents and trashed=false"
            files_json=$(curl -s -G -H "Authorization: Bearer $access_token" \
                --data-urlencode "q=$query_param" \
                --data-urlencode "fields=files(name,mimeType)" \
                --data-urlencode "orderBy=name" \
                --data-urlencode "supportsAllDrives=true" \
                --data-urlencode "includeItemsFromAllDrives=true" \
                "https://www.googleapis.com/drive/v3/files")
            
            # Check for API errors in file listing
            if echo "$files_json" | grep -q '"error"'; then
                error_msg=$(echo "$files_json" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
                echo "Error listing files: ${error_msg:-Unknown error}"
                echo "Response: $files_json"
                exit 1
            fi
            
            # Parse and display file names
            # Check if files array exists in response
            if echo "$files_json" | grep -q '"files"'; then
                if command -v jq >/dev/null 2>&1; then
                    file_count=$(echo "$files_json" | jq '.files | length' 2>/dev/null)
                    # Ensure file_count is a valid number
                    if [ -z "$file_count" ] || [ "$file_count" = "null" ]; then
                        file_count=0
                    fi
                    if [ "$file_count" -gt 0 ] 2>/dev/null; then
                        echo "$files_json" | jq -r '.files[] | "  - \(.name)"' 2>/dev/null
                    else
                        echo "  (No files found)"
                    fi
                else
                    # Fallback: use grep/sed - extract all file names
                    file_names=$(echo "$files_json" | grep -o '"name":"[^"]*"' | sed 's/"name":"\([^"]*\)"/\1/')
                    if [ -n "$file_names" ]; then
                        echo "$file_names" | while IFS= read -r filename; do
                            if [ -n "$filename" ]; then
                                echo "  - $filename"
                            fi
                        done
                    else
                        echo "  (No files found)"
                    fi
                fi
            else
                # No files array in response - might be empty or error
                if echo "$files_json" | grep -q '"files":\[\]'; then
                    echo "  (No files found)"
                else
                    echo "  (Unable to parse file list - response: $files_json)"
                fi
            fi
        else
            echo "Listing drives root files...";
            curl -s -H "GData-Version: 3.0" -H "Authorization: Bearer $access_token" https://www.googleapis.com/drive/v2/files
        fi
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
