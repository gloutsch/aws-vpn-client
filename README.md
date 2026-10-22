# aws-vpn-client

Connect to the AWS Client VPN with OSS OpenVPN using SAML authentication.

This repository is a fork of
[aws-vpn-client/aws-vpn-client](https://github.com/aws-vpn-client/aws-vpn-client).
See [the blog post](https://smallhacks.wordpress.com/2020/07/08/aws-client-vpn-internals/)
for the implementation details. The DNS hook needs Linux with systemd-resolved.

## Content of the repository

- `openvpn-vX.Y.Z-aws.patch` - patch required to build an AWS compatible
OpenVPN vX.Y.Z. Current: [openvpn-v2.7.8-aws.patch](openvpn-v2.7.8-aws.patch).
Older versions are at the matching `openvpn-vX.Y.Z` tags.
[PATCH_UPGRADE_NOTES.md](PATCH_UPGRADE_NOTES.md) describes how to port it to a new OpenVPN version.
- [server.go](server.go) - Go server listening on http://127.0.0.1:35001 that saves the SAML POST data to `saml-response.txt`
- [aws-connect.sh](aws-connect.sh) - bash wrapper to run OpenVPN. It runs OpenVPN first to get the SAML redirect, opens the browser, then runs OpenVPN again with the actual SAML response
- [resolvconf.sh](resolvconf.sh) - OpenVPN `up`/`down` hook. It registers the pushed DNS servers with `resolvconf`, adds the routing domains from [domains.txt](domains.txt) and disables DNSSEC and DNS over TLS on the tunnel link
- [vpn.conf](vpn.conf) - sample OpenVPN configuration
- [build.yaml](.github/workflows/build.yaml) - CI build of the patched OpenVPN and `SAMLserver`
- [latest-openvpn-version.sh](latest-openvpn-version.sh) - prints the latest stable OpenVPN release

## How to use

1. Get the binaries: download `aws-vpn-client-vX.Y.Z-linux-x86_64.tar.gz` from the [releases](https://github.com/gloutsch/aws-vpn-client/releases) and verify it with the `.sha256` file. It is built on Ubuntu; on other distributions apply the patch to the matching OpenVPN release, build it and run `go build -o SAMLserver server.go`
1. Keep `openvpn`, `SAMLserver`, `aws-connect.sh`, `resolvconf.sh`, `vpn.conf`, `domains.txt` and your CA file in one directory; the scripts use relative paths
1. Run `./aws-connect.sh --host <vpn-host> --ca <ca.pem>`. Optional: `--port` (default 1194), `--timeout` (seconds to wait for the SAML response, default 300), `--config`, `--bin`

Requires `sudo`, a browser opener (`xdg-open`), and `resolvconf` and `resolvectl` for the DNS hook.

### Additional Steps

Inspect your ovpn config and remove the following lines if present
- `auth-user-pass` (we dont want to show user prompt)
- `auth-federate` (propietary AWS keyword)
- `auth-retry interact` (do not retry on failures)
- `remote` and `remote-random-hostname` (already handled in CLI and can cause conflicts with it)

## Releasing

A release is a tag `openvpn-vX.Y.Z` on a commit that contains
`openvpn-vX.Y.Z-aws.patch`. Pushing the tag runs the build, which applies the
patch to OpenVPN vX.Y.Z, builds OpenVPN and `SAMLserver`, and publishes a GitHub
release with `aws-vpn-client-vX.Y.Z-linux-x86_64.tar.gz` and its `.sha256`. The
build can also be started by hand with
`gh workflow run build.yaml -f openvpn_version=vX.Y.Z`; a manual run only keeps
the tarball as a workflow artifact and publishes no release.

`./latest-openvpn-version.sh [series]` prints the latest stable OpenVPN release
(for example `2.6` for that series) and tells whether its patch exists.

## Todo

Better integrate SAML HTTP server with a script or rewrite everything on golang
