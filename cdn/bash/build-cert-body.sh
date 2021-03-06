#!/bin/bash
set -e

if [ $# -lt 1 ]; then
    echo "Usage:"
    echo "$0 {certificate}.json [-k {privateKey}.pem -d {dateString}] [-c {cert}.pem] [-a {CAcert}.pem]"
    echo "This script takes a base json that describes a certificate, and optionally"
    echo "the private key, certificate and CA certificate files. It outputs the merged"
    echo "json file to the stdout. When the private key is provided, a dateString is also"
    echo "required to construct the encryption key."
    echo "The json file has to terminate with a newline, and contains"
    echo "\"privateKey\": _PRIVATE_KEY_"
    echo "\"certificate\": _CERTIFICATE_"
    echo "\"chainCert\": _CA_CERTIFICATE_"
    echo "each on a dedicated line."
    exit 0;
fi

appname=$0
while readlink "${appname}" > /dev/null; do
  appname=`readlink "${appname}"`
done
appdir=$(dirname "${appname}")
jsonfn=$1
shift
privkeyfn=
datestr=
certfn=
cacertfn=

while getopts "k:d:c:a:" options; do
  case "${options}" in                          
    d)
      datestr="${OPTARG}"
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

enckey=
if [ -z "$privkeyfn" ]; then
  >&2 echo "no private key file is provided!";
elif [ -f "$privkeyfn" ]; then
  [ -z "$datestr" ] && ( >&2 echo "missing datestr!"; exit 1; )
  if [ -f ./SECRET_api_credential.txt ]; then
    source ./SECRET_api_credential.txt
  else
    source $appdir/SECRET_api_credential.txt
  fi
  passw=$(echo -n "$datestr" | openssl dgst -sha256 -hmac "$API_KEY" -r)
  aes128cbciv=${passw:0:32}
  aes128cbckey=${passw:32:32}
  enckey=$(cat $privkeyfn | openssl aes-128-cbc -base64 -nosalt -K $aes128cbckey -iv $aes128cbciv | $appdir/jsonesc.sh -)
else
  >&2 echo "Could not find file $privkeyfn, exiting.";
  exit 1;
fi

while IFS= read -r line
do
  if echo "$line" | grep -q '"privateKey" *: *_PRIVATE_KEY_'; then
    if [ -z "$enckey" ]; then 
      >&2 echo "$jsonfn contains _PRIVATE_KEY_ but missing private key file!";
      echo "$line" | sed 's/_PRIVATE_KEY_/null/';
    else
      esc2=${enckey//\\/\\\\}   #some additional substitutions for sed
      esc3=${esc2//\//\\/}
      echo "$line" |sed "s/_PRIVATE_KEY_/\"$esc3\"/"
    fi
  elif echo "$line" | grep -q '"certificate" *: *_CERTIFICATE_'; then
    if [ -z "$certfn" ]; then
      >&2 echo "$jsonfn contains _CERTIFICATE_ but missing certificate file!";
      echo "$line" | sed 's/_CERTIFICATE_/null/';
    elif [ ! -f "$certfn" ]; then
      >&2 echo "Could not find file $certfn, exiting.";
      exit 1;
    else
      esc1=$($appdir/jsonesc.sh $certfn)
      esc2=${esc1//\\/\\\\}   #some additional substitutions for sed
      esc3=${esc2//\//\\/}
      echo "$line" |sed "s/_CERTIFICATE_/\"$esc3\"/"
    fi
  elif echo "$line" | grep -q '"chainCert" *: *_CA_CERTIFICATE_'; then
    if [ -z "$cacertfn" ]; then
      >&2 echo "$jsonfn contains _CA_CERTIFICATE_ but missing CA certificate file!";
      echo "$line" | sed 's/_CA_CERTIFICATE_/null/';
    elif [ ! -f "$cacertfn" ]; then
      >&2 echo "Could not find file $cacertfn, exiting.";
      exit 1;
    else
      esc1=$($appdir/jsonesc.sh $cacertfn)
      esc2=${esc1//\\/\\\\}   #some additional substitutions for sed
      esc3=${esc2//\//\\/}
      echo "$line" |sed "s/_CA_CERTIFICATE_/\"$esc3\"/"
    fi
  else
      echo "$line"
  fi
done < "$jsonfn"
