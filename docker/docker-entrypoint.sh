#!/bin/bash
#!/bin/bash
set -e

# We translate environment variables to sdc.properties and rewrite them.
set_conf() {
  if [ $# -ne 2 ]; then
    echo "set_conf requires two arguments: <key> <value>"
    exit 1
  fi

  if [ -z "$SDC_CONF" ]; then
    echo "SDC_CONF is not set."
    exit 1
  fi

  sed -i 's|^#\?\('"$1"'=\).*|\1'"$2"'|' "${SDC_CONF}/sdc.properties"
}

# In some environments such as Marathon $HOST and $PORT0 can be used to
# determine the correct external URL to reach SDC.
if [ ! -z "$HOST" ] && [ ! -z "$PORT0" ] && [ -z "$SDC_CONF_SDC_BASE_HTTP_URL" ]; then
  export SDC_CONF_SDC_BASE_HTTP_URL="http://${HOST}:${PORT0}"
fi

for e in $(env); do
  key=${e%=*}
  value=${e#*=}
  if [[ $key == SDC_CONF_* ]]; then
    lowercase=$(echo $key | tr '[:upper:]' '[:lower:]')
    key=$(echo ${lowercase#*sdc_conf_} | sed 's|_|.|g')
    set_conf $key $value
  fi
done

# log into dpm, get auth token, register, save and startup sdc
echo "Login and generate authentication token"

USERNAME=$(cat /var/lib/sdc-resources/dpmuser)
PASSWORD=$(cat /var/lib/sdc-resources/dpmpassword)

# login to security app
curl -X POST -d "{\"userName\":\"${USERNAME}\", \"password\": \"${PASSWORD}\"}" ${URL}/security/public-rest/v1/authentication/login --header "Content-Type:application/json" --header "X-Requested-By:SDC" -c /tmp/cookie.txt

# generate auth token from security app
sessionToken=`sed -n '/SS-SSO-LOGIN/p' /tmp/cookie.txt | perl -lane 'print $F[$#F]'`

touch /tmp/authToken.txt

curl -X PUT -d "{\"organization\": \"${ORG}\", \"componentType\" : \"dc\", \"numberOfComponents\" : 1, \"active\" : true}" ${URL}/security/rest/v1/organization/${ORG}/components --header "Content-Type:application/json" --header "X-Requested-By:SDC" --header "X-SS-REST-CALL:true" --header "X-SS-User-Auth-Token:$sessionToken" > /tmp/authToken.txt

# copy app token to sds.properties file
authToken=`jq --raw-output '.[0]|.fullAuthToken' /tmp/authToken.txt`

echo "Modifying sdc.properties"

echo "$authToken" > "${SDC_CONF}/application-token.txt"
sed -i "s|dpm.enabled=.*|dpm.enabled=true|" ${SDC_CONF}/dpm.properties
sed -i "s|dpm.base.url=.*|dpm.base.url=${URL}|" ${SDC_CONF}/dpm.properties
sed -i "s|dpm.remote.control.job.labels=.*|dpm.remote.control.job.labels=${LABELS}|" ${SDC_CONF}/dpm.properties

exec "${SDC_DIST}/bin/streamsets" "$@"
