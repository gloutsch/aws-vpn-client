#!/usr/bin/env bash

set -e

PORT=1194
OVPN_BIN="./openvpn"
OVPN_CONF="vpn.conf"
PROTO=udp

function usage {
  echo "usage: $0 [options] --host host --ca pemfile"
  echo "options:"
  echo -e "\t-h --help\tshow thelp"
  echo -e "\t--port\t\topenvpn remote port"
  echo -e "\t--proto\t\topenvpn protocol"
  echo -e "\t--config\topenvpn config"
  echo -e "\t--bin\t\topenvpn binary"
  exit 1
}

# parse options
while [[ -n "$1" ]]; do
  case "$1" in
    -h*) usage ;;
    --help) usage ;;
    --host) VPN_HOST="$2"; shift ;;
    --port) PORT="$2"; shift ;;
    --config) OVPN_CONF="$2"; shift ;;
    --bin) OVPN_BIN="$2"; shift ;;
    --ca) OVPN_CA="$2"; shift ;;
  esac
  shift
done

# test cli options
[[ -z "$VPN_HOST" || -z "$OVPN_CA" ]] && usage

# test openvpn executable
[[ -f "$OVPN_BIN" && -x "$OVPN_BIN" ]] || {
  echo "Cannot execute $OVPN_BIN"
  exit 1
}

wait_file() {
  local file="$1"; shift
  local wait_seconds="${1:-10}"; shift # 10 seconds as default timeout
  until test $((wait_seconds--)) -eq 0 -o -f "$file" ; do sleep 1; done
  ((++wait_seconds))
}

# resolv manually hostname to IP, as we have to keep persistent ip address
SRV=$(dig A +short "${VPN_HOST}"| grep -v amazon | head -n1)

# cleanup
rm -f saml-response.txt

pkill SAMLserver || :
./SAMLserver & sleep 1

echo "Getting SAML redirect URL from the AUTH_FAILED response (host: ${SRV}:${PORT})"
OVPN_OUT=$($OVPN_BIN --config "${OVPN_CONF}" --verb 3 \
                     --proto "$PROTO" --remote "${SRV}" "${PORT}" --ca "$OVPN_CA" \
                     --auth-user-pass <( printf "%s\n%s\n" "N/A" "ACS::35001" ) \
                     2>&1 | grep AUTH_FAILED,CRV1)

echo "Opening browser and wait for the response file..."
URL=$(echo "$OVPN_OUT" | grep -Eo 'https://.+')

unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     xdg-open "$URL";;
    Darwin*)    open "$URL";;
    *)          echo "Could not determine 'open' command for this OS"; exit 1;;
esac

wait_file "saml-response.txt" 60 || {
  echo "SAML Authentication time out"
  exit 1
}

pkill SAMLserver

# get SID from the reply
VPN_SID=$(echo "$OVPN_OUT" | awk -F : '{print $7}')

echo "Running OpenVPN with sudo. Enter password if requested"

# Finally OpenVPN with a SAML response we got
# Delete saml-response.txt after connect
sudo bash -c "$OVPN_BIN --config "${OVPN_CONF}" \
    --verb 4 --auth-nocache --inactive 3600 \
    --proto "$PROTO" --remote $SRV $PORT --ca "$OVPN_CA" \
    --script-security 2 \
    --route-up '/usr/bin/env rm saml-response.txt' \
    --auth-user-pass <( printf \"%s\n%s\n\" \"N/A\" \"CRV1::${VPN_SID}::$(cat saml-response.txt)\" )"
