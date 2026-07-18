#!/bin/bash
set -e

if [ $# -lt 2 ]; then
    echo "Usage:"
    echo "$0 {method} {uri} [options]"
    echo ""
    echo "{method} can be GET, POST, PUT, PATCH or DELETE"
    echo "{url} can be /properties, /certificates etc"
    echo "[options] can be: -j {json filename for request body}"
    echo "                  -d # add the x-debug header"
    echo "                  -i {child customer ID to impersonate}"
    echo "                  -H 'headerName: headerValue' # add additional request header"
    echo "                  -p # prettify the json body (works on Mac or with nodejs)"
    echo "                  -A # set header Report-Range:self+children"
    echo "                  -v {verbose level 0-4} # >=3 has respose headers in stdout"
    echo "                  -k {private key file in PEM format}"
    echo "                  -c {certificate file in PEM format}"
    echo "                  -a {CA certificate file in PEM format}"
    echo "                  -l {date range by ymwdHMS: 2d means the last 2 days.}"
    echo "                  -m {date range of a month or a day. e.g. 2020-01, 2020-02-01}"
    echo "                  -e {edge logic file}"
    echo "                  -b {json body}"
    echo "                  -r # refresh the cached response"
    echo "Note: You need to put your API username and key in a file named"
    echo "SECRET_api_credential.txt under the same directory."
    echo ""
    echo "Some common tasks:"
    echo "$0 GET /properties                               #query property list"
    echo "$0 GET /properties/{id}                          #query one property"
    echo "$0 GET /properties/{id}/versions                 #query versions list"
    echo "$0 GET /properties/{id}/versions/{ver}           #query one property version"
    echo "$0 POST /properties -j {body}.json -e {edgelogic}.el     #create a new property"
    echo "$0 POST /properties/{id}/versions -j {body}.json -e {edgelogic}.el"
    echo "                                                 #create a new property version"
    echo "$0 PATCH /properties/{id}/versions/{version} -j {body}.json -e {edgelogic}.el"
    echo "                                                 #update a version"
    echo "$0 PATCH /properties/{id} -j {body}.json         #update a property"
    echo "$0 DELETE /properties/{id}                       #delete a property"
    echo "$0 GET /certificates                             #query certificate list"
    echo "$0 GET /certificates/{id}                        #query one certificate"
    echo "$0 GET /certificates/{id}/csr                    #download the CSR"
    echo "$0 GET /certificates/{id}/versions/{ver}         #query one certificate version"
    echo "$0 POST /certificates -j {body}.json [-k key.pem] [-c cert.pem] [-a cacert.pem]"
    echo "                                                 #create a new certificate"
    echo "$0 PATCH /certificates/{id} -j {body}.json [-k key.pem] [-c cert.pem] [-a cacert.pem]"
    echo "                                                 #update a certificate"
    echo "$0 DELETE /certificates/{id}                     #delete a certificate"
    echo "$0 POST /validations -j {body}.json              #create a validation task"
    echo "$0 GET /validations                              #query validation task list"
    echo "$0 GET /validations/{id}                         #query one validation task"
    echo "$0 POST /deploymentTasks -j {body}.json          #create a deployment task"
    echo "$0 GET /deploymentTasks                          #query deployment task list"
    echo "$0 GET /deploymentTasks/{id}                     #query a deployment task"
    echo "$0 POST /edgeHostnames -j {body}.json            #create an edge hostname"
    echo "$0 GET /edgeHostnames                            #query edge hostname list"
    echo "$0 GET /edgeHostnames/{id}                       #query an edge hostname"
    echo "$0 PUT /edgeHostnames/{id}                       #updae an edge hostname"
    echo "$0 DELETE /edgeHostnames/{id}                    #delete an edge hostname"
    echo "dig staging.qtlgslb.com                          #query the staging server IPs"
    exit 0;
fi

appname=$0
uribase=/cdn
[[ ${appname} == *adminapi.sh ]] && uribase=/ngadmin
[[ ${appname} == *roleapi.sh ]] && uribase=/ngrole
[[ ${appname} == *hdtapi.sh ]] && uribase=/hdt

while readlink "${appname}" > /dev/null; do
  appname=`readlink "${appname}"`
done
appdir=$(dirname "${appname}")
if [[ $1 == /* ]]; then
  method=GET
else
  method=$1
  shift 1;
fi
uri=$1
shift 1;

jsonfn=
privkeyfn=
certfn=
cacertfn=
edgelogicfn=
headers=
jsonpp=
jsonbody=
verblevel=2
verbopt="-vSs"

while getopts "j:dH:i:pk:c:a:e:b:v:l:m:Ar" options; do
  case "${options}" in                          
    j)
      jsonfn=${OPTARG}
      ;;
    d)
      headers+=" -H 'x-debug: true'"
      ;;
    i)
      headers+=" -H 'on-behalf-of: ${OPTARG}'"
      ;;
    H)
      headers+=" -H '${OPTARG}'"
      ;;
    A)
      headers+=" -H 'Report-Range:self+children'"
      ;;
    r)
      headers+=" -H 'cache-control:no-cache'"
      ;;
    p)
      if node -v > /dev/null; then
        jsonpp='|grep ^[[{]|node "'${appdir}'/../../common/json_pp.js"'
      elif json_pp -V > /dev/null; then
        jsonpp='|grep ^[[{]|json_pp'
      fi
      ;;
    k)
      privkeyfn="${OPTARG}"
      ;;
    c)
      certfn="${OPTARG}"
      ;;
    a)
      cacertfn="${OPTARG}"
      ;;
    e)
      edgelogicfn="${OPTARG}"
      ;;
    b)
      jsonbody="${OPTARG}"
      ;;
    l)
      enddate=$(LC_TIME="C" date -u "+%Y-%m-%dT%H:%M:%SZ")
      if [ $(uname) = 'Linux' ]; then
        case "${OPTARG}" in
          *y)   #year
            st=${OPTARG}ear
            ;;
          *m)  #month
            st=${OPTARG}onth
            ;;
          *w)  #week
            st=${OPTARG}eek
            ;;
          *d)  #day
            st=${OPTARG}ay
            ;;
          *H)  #Hour
            st=${OPTARG}our
            ;;
          *M)  #Minute
            st=${OPTARG}inute
            ;;
          *S)  #Second
            st=${OPTARG}econd
            ;;
          *)
            st=${OPTARG}
            ;;
        esac
        startdate=$(LC_TIME="C" date -d -${st} -u "+%Y-%m-%dT%H:%M:%SZ")
      else
        startdate=$(LC_TIME="C" date -v -${OPTARG} -u "+%Y-%m-%dT%H:%M:%SZ")
      fi
      daterange="startdate=${startdate}&enddate=${enddate}"
      echo "$uri" | grep "?" && daterange="&"$daterange || daterange="?"$daterange
      ;;
    m)
      month2d=(00 01 02 03 04 05 06 07 08 09 10 11 12)
      monthdays1=(0 31 28 31 30 31 30 31 31 30 31 30 31)
      year=${OPTARG%%-*}
      month="${OPTARG#*-}"
      if echo "${month}" | grep -q -; then
        day="${month#*-}"
        month=${month%-*}
      fi
      monthn=${month#0}
      month=${month2d[${monthn}]}
      if [ ${day} ]; then
        startday=${day}
        endday=${day}
      else
        startday=01
        endday=${monthdays1[${monthn}]}
        rem=$(expr ${year} % 4 + 1)
        if [ "${month}" = 02 -a "${rem}" = 1 ]
        then endday=29
        fi
      fi
      startdate="${year}-${month}-${startday}T00:00:00Z"
      enddate="${year}-${month}-${endday}T23:59:59Z"
      daterange="startdate=${startdate}&enddate=${enddate}"
      echo "$uri" | grep "?" && daterange="&"$daterange || daterange="?"$daterange
      ;;
    v)
      verblevel=${OPTARG}
      if [ ${OPTARG} -lt 2 ]; then verbopt="-sS"
      elif [ ${OPTARG} = 3 ]; then verbopt="-isS"
      elif [ ${OPTARG} = 4 ]; then verbopt="-visS"
      fi
      ;;
    :)
      echo "Error: -${OPTARG} requires an argument."
      exit 1
      ;;
    *)
      echo "Error: unknown input error."
      exit 1
      ;;
  esac
done

API_SERVER_NAME=ngapi.cdnetworks.com

#This file should contain the definition of two variables:
#USER='Your API username'
#API_KEY='You API key'
if [ -f ./SECRET_api_credential.txt ]; then
  source ./SECRET_api_credential.txt
else
  source $appdir/SECRET_api_credential.txt
fi
if [ $API_SERVER_IP ]; then
  resolve="-k --resolve $API_SERVER_NAME:443:$API_SERVER_IP"
fi
if [ $API_SERVER_ALIAS ]; then
  resolve="-k --connect-to $API_SERVER_NAME:443:$API_SERVER_ALIAS"
fi
DATE=`LC_TIME="C" date -u "+%a, %d %b %Y %H:%M:%S GMT"`
#echo $DATE
# Generate authentication info
passw=$(echo -n "$DATE" | openssl dgst -sha1 -hmac "$API_KEY" -binary | base64)
#echo $passw
[[ $uri == /auth ]] && uribase=
api_curl_cmd="curl ${verbopt} --url
 'https://${API_SERVER_NAME}${uribase}$uri$daterange' -X $method --compressed
            -u '$USER:$passw'
			-H 'Date: $DATE'
			-H 'Content-Type: application/json'
			-H 'Accept: application/json'
      -H 'User-Agent: CDNProCLI-bash/1.0'
			$headers
			$resolve
"
tempfn=
if [ "$method" = "POST" -o "$method" = "PUT" -o "$method" = "PATCH" ]; then
  if [ -f "$jsonfn" ]; then
    case "$uri" in
      /properties*)
        if [ -f "$edgelogicfn" ]; then
          tempfn=$(mktemp ./property.json.XXXXXX)
          ${appdir}/build-property-body.sh "$jsonfn" "$edgelogicfn" > "$tempfn" ||
            ( rm "$tempfn"; exit 1 )
          jsonfn="$tempfn"
        fi
        ;;
      /certificates*)
        tempfn=$(mktemp ./cert.json.XXXXXX)
        certcmd="${appdir}/build-cert-body.sh '$jsonfn' "
        [ -f "$privkeyfn" ] && certcmd+="-k '$privkeyfn' -d '$DATE' "
        [ -f "$certfn" ] && certcmd+="-c '$certfn' "
        [ -f "$cacertfn" ] && certcmd+="-a '$cacertfn'"
        eval $certcmd > "$tempfn" ||
          ( rm "$tempfn"; exit 1 )
        jsonfn="$tempfn"
        ;;
    esac
    api_curl_cmd+=" -d @'$jsonfn'"
  elif [ "$jsonbody" ]; then
    escaped_jsonbody=$(echo "$jsonbody" | sed "s/'/'\\\''/g")
    api_curl_cmd+=" -d '$escaped_jsonbody'"
  else
    echo "Method \"$method\" requires a valid json file to be specified after -j"
    echo "                   or a json body specified after -b"
    exit 1
  fi
fi

[ $verblevel = 0 ]||echo $api_curl_cmd $jsonpp>& 2
#exit  #for testing
eval $api_curl_cmd $jsonpp
echo " "
[ -f "$tempfn" ] && rm "$tempfn"
exit 0;
