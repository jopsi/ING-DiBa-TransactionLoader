#!/bin/bash
touch arcookies
rm arcookies*

#-------- Enter here your 6 digit keypad code --------
KEYPADCODE="123456"
#-------- Enter here your last 10 digits of your account ---------
ACCOUNTID="1234567890"
#-------- Enter here your account pin ---------
ACCOUNTPIN="mypin"

if [ $ACCOUNTPIN == "mypin" ]; then
  echo "please configure the script"
  exit
fi

function getPage() {
  cookieFile="${1}"
  url="${2}"
  outputFile="${3}"
  wget -S --save-cookies ${cookieFile} --save-headers --load-cookies ${cookieFile} \
    --keep-session-cookies --no-check-certificate --ca-certificate=./cacert.pem \
    ${url} -a logFile.txt --output-document=${outputFile}
}

function postPage() {
  cookieFile="${1}"
  url="${2}"
  outputFile="${3}"
  postparam="${4}"
  wget --post-data "${postparam}" -S --save-cookies ${cookieFile} --save-headers \
    --load-cookies ${cookieFile} --keep-session-cookies --no-check-certificate \
    --ca-certificate=./cacert.pem ${url} -a logFile.txt --output-document=${outputFile}
}

function extractRelativeURL() {
  elementPattern="${1}"
  urlpattern="${2}=\"[^\"]*"
  sedpurgepattern="s/${2}=\"[\/\.]*//"
  file="${3}"
  grep "${elementPattern}" "${file}" | grep -o $urlpattern | sed $sedpurgepattern
}

function getKeyPadAnswer() {
  file="${1}"
  INDEXES=$(grep -o "key:key:keypadinput:values:[0-5]:inputvalue" ${file} | cut -d":" -f 5)
 
  if [ "$INDEXES" == "" ]; then
    exit
  fi
  
  while read -r idx; do
    code=${KEYPADCODE:${idx}:1}
    echo -n "key%3Akey%3Akeypadinput%3Avalues%3A${idx}%3Ainputvalue=${code}&"
  done <<< "${INDEXES}"
  echo -n "token%3Aform%3Atoken="
  token=$(extractRelativeURL "name=\"token:form:token\"" "value" ${file})
  echo -n $token
  echo "&weiter_finish="
}

function extractLinkAndIBAN() {
  file=${1}
  egrep "\"g2p-account__row\"|\"g2p-account__iban\"" ${file} | \
    egrep -o ">[A-Z0-9 ]*<|href=\"[^\"]*" | \
      sed "s/href=\"\.//;s/[\>\<]*//g"
}

#-------------------------------------------------------------
# Call login page to get initial cookie and credentials
#-------------------------------------------------------------
BASEURL="https://banking.ing-diba.de/app/"
getPage arcookies ${BASEURL} content_login.html

#-------------------------------------------------------------
# Call INGDIBA Keypage with kto & pin
#-------------------------------------------------------------
URL=${BASEURL}$(extractRelativeURL " method=\"post\" action=\"./login" \
                                   "action" "content_login.html")
postPage arcookies ${URL} content_keypage.html "zugangskennung%3Azugangskennung=${ACCOUNTID}&pin%3Apin=${ACCOUNTPIN}&browserInfo%3Apostback%3AnavigatorAppName=Netscape&browserInfo%3Apostback%3AnavigatorAppVersion=5.0+%28Windows+NT+6.1%3B+Win64%3B+x64%29+AppleWebKit%2F537.36+%28KHTML%2C+like+Gecko%29+Chrome%2F71.0.3578.98+Safari%2F537.36&browserInfo%3Apostback%3AnavigatorAppCodeName=Mozilla&browserInfo%3Apostback%3AnavigatorCookieEnabled=true&browserInfo%3Apostback%3AnavigatorJavaEnabled=false&browserInfo%3Apostback%3AnavigatorLanguage=de-DE&browserInfo%3Apostback%3AnavigatorPlatform=Win32&browserInfo%3Apostback%3AnavigatorUserAgent=Mozilla%2F5.0+%28Windows+NT+6.1%3B+Win64%3B+x64%29+AppleWebKit%2F537.36+%28KHTML%2C+like+Gecko%29+Chrome%2F71.0.3578.98+Safari%2F537.36&browserInfo%3Apostback%3AscreenWidth=1920&browserInfo%3Apostback%3AscreenHeight=1080&browserInfo%3Apostback%3AscreenColorDepth=24&browserInfo%3Apostback%3AutcOffset=1&browserInfo%3Apostback%3AutcDSTOffset=2&browserInfo%3Apostback%3AbrowserWidth=1434&browserInfo%3Apostback%3AbrowserHeight=1510&browserInfo%3Apostback%3Ahostname=banking.ing-diba.de&browserInfo%3Apostback%3AinputtypeSearch=true&browserInfo%3Apostback%3AinputtypeNumber=true&browserInfo%3Apostback%3AinputtypeRange=true&browserInfo%3Apostback%3AinputtypeColor=true&browserInfo%3Apostback%3AinputtypeTel=true&browserInfo%3Apostback%3AinputtypeUrl=true&browserInfo%3Apostback%3AinputtypeEmail=true&browserInfo%3Apostback%3AinputtypeDate=true&browserInfo%3Apostback%3AinputtypeMonth=true&browserInfo%3Apostback%3AinputtypeWeek=true&browserInfo%3Apostback%3AinputtypeTime=true&browserInfo%3Apostback%3AinputtypeDatetime=false&browserInfo%3Apostback%3AinputtypeDatetimeLocal=true"

#-------------------------------------------------------------
# Answer INGDIBA key challenge
#-------------------------------------------------------------
POSTPARAM=$(getKeyPadAnswer "content_keypage.html")
if [ "$POSTPARAM" == "" ]; then
  echo 'ERROR: There is something wrong with the login.'
  echo 'Please see with lynx in content_keypage.html for error messages.'
  exit
fi
  
URL=${BASEURL}$(extractRelativeURL " method=\"post\" action=\"" \
                             "action" content_keypage.html)
postPage arcookies ${URL} content_entrypage.html ${POSTPARAM}

#-------------------------------------------------------------
# Export overview CSV file
#-------------------------------------------------------------
URL=${BASEURL}$(extractRelativeURL "link-icon--export" "href" content_entrypage.html)
getPage arcookies ${URL} overview.csv

#-------------------------------------------------------------
# Iterate over all accounts and export the transaction CSV
# file by extracting the urls the accounts and the iban of the 
# accounts
#-------------------------------------------------------------
KONTEN=$(extractLinkAndIBAN content_entrypage.html)
if [ "$KONTEN" == "" ]; then
  echo 'ERROR: There is something wrong with the keypadcode .'
  echo 'Please see with lynx in content_entrypage.html for error messages.'
  exit
fi

while read -r accountURL; do
    read -r iban
    outputFile=$(echo $iban | tr -d " ")".html"
    url=${BASEURL:0:$((${#BASEURL}-1))}${accountURL} 
    getPage arcookies ${url} ${outputFile}
    url=${BASEURL}$(extractRelativeURL "data-click-action=\"csv.banking.link\"" "href" ${outputFile})
    getPage arcookies ${url} ${outputFile:0:$((${#outputFile}-5))}.csv
done <<< "$KONTEN"
