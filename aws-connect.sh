#!/usr/bin/env bash

set -e

PORT=1194
OVPN_BIN="./openvpn"
OVPN_CONF="vpn.conf"
PROTO=udp

function usage {
  echo "usage: $0 [options] --host host --ca pemfile"
  echo "options:"
  echo -e "\t-h --help\tshow help"
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
if [[ -z "$VPN_HOST" || -z "$OVPN_CA" ]]; then
  echo "Error: Missing required arguments."
  usage
fi

# test openvpn executable
[[ -f "$OVPN_BIN" && -x "$OVPN_BIN" ]] || {
  echo "Cannot execute $OVPN_BIN"
  exit 1
}

wait_file() {
  local file="$1"; shift
  local wait_seconds="${1:-10}"; shift # 10 seconds as default timeout
  # We use a loop with short sleeps so that we remain responsive to interrupts.
  # The trap will clean up background processes if interrupted.
  while [[ $wait_seconds -gt 0 ]]; do
    if [[ -f "$file" ]]; then
      return 0
    fi
    sleep 1
    ((wait_seconds--))
  done
  return 1
}

# resolv manually hostname to IP, as we have to keep persistent ip address
SRV=$(dig A +short "${VPN_HOST}" | grep -v amazon | head -n1)
if [[ -z "$SRV" ]]; then
  echo "Error: Failed to resolve VPN hostname ${VPN_HOST}"
  exit 1
fi

# cleanup
rm -f saml-response.txt

# Ensure SAMLserver is stopped on exit, interrupt, or error
trap '[[ -n "$SAML_PID" ]] && kill "$SAML_PID" 2>/dev/null || :' EXIT INT TERM

./SAMLserver &
SAML_PID=$!
sleep 1

echo "Getting SAML redirect URL from the AUTH_FAILED response (host: ${SRV}:${PORT})"
OVPN_OUT=$("$OVPN_BIN" --config "${OVPN_CONF}" --verb 3 \
                     --proto "$PROTO" --remote "${SRV}" "${PORT}" --ca "$OVPN_CA" \
                     --auth-user-pass <( printf "%s\n%s\n" "N/A" "ACS::35001" ) \
                     2>&1 | grep AUTH_FAILED,CRV1 || true)

URL=$(echo "$OVPN_OUT" | grep -Eo 'https://.+')

if [[ -z "$URL" ]]; then
  echo "Error: Failed to retrieve SAML redirect URL from OpenVPN output."
  echo "OpenVPN Output:"
  echo "$OVPN_OUT"
  exit 1
fi

echo "Opening browser and wait for the response file..."
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

# We successfully got the response; kill the server immediately.
# We also unset SAML_PID so the EXIT trap ignores it.
kill "$SAML_PID" 2>/dev/null || :
unset SAML_PID

# get SID from the reply
VPN_SID=$(echo "$OVPN_OUT" | awk -F : '{print $7}')

echo "Running OpenVPN with sudo. Enter password if requested"

# Finally OpenVPN with a SAML response we got
# Delete saml-response.txt after connect
sudo bash -c "\"$OVPN_BIN\" --config \"${OVPN_CONF}\" \
    --verb 4 --auth-nocache --inactive 3600 \
    --proto \"$PROTO\" --remote \"$SRV\" \"$PORT\" --ca \"$OVPN_CA\" \
    --script-security 2 \
    --route-up '/usr/bin/env rm saml-response.txt' \
    --auth-user-pass <( printf \"%s\n%s\n\" \"N/A\" \"CRV1::${VPN_SID}::\$(cat saml-response.txt)\" )"
