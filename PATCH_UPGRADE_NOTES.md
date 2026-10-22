# Patch Upgrade Notes

This repository carries a small AWS Client VPN compatibility patch on top of upstream OpenVPN. When upgrading OpenVPN, keep the patch semantics intact and only adapt the surrounding context to upstream code changes.

## Patch Invariants

The AWS patch is intended to preserve these behaviours:

1. Increase buffer and option sizes so large AWS SAML authentication payloads can pass through OpenVPN.
2. Use 32-bit string length fields in the TLS key method payload instead of upstream 16-bit fields.
3. Write the key-method payload length into the first 4 octets of the buffer before sending it.
4. Increase management socket and command-line buffers so the larger auth payload is not truncated.

## Upgrading from v2.6.13 to v2.7.5

During the upgrade to v2.7.5, the following upstream changes required adaptations in the v2.7.5 patch (`openvpn-v2.7.5-aws.patch`, since replaced by `openvpn-v2.7.8-aws.patch`; see git history):

1. **`manage.c` (Type Changes):**
   Upstream updated the socket `len` variable from `int` to `ssize_t` to be more compliant with standard network APIs. The patch context had to be updated to match the new `ssize_t len = 0;` line.

2. **`ssl.c` (`write_string` Length Handling):**
   Upstream v2.7.5 now clamps string lengths with `UINT16_MAX` and explicitly casts to `(uint16_t)len` before calling `buf_write_u16()`. The AWS compatibility patch must keep the 32-bit length semantics, so this was adapted to `UINT32_MAX`, `(uint32_t)len`, and `buf_write_u32()`.

3. **`ssl.c` (Key Method Length Prefix):**
   The existing AWS behaviour that writes `BLEN(buf)` into the first 4 octets of the key-method buffer is still required and was retained.

## Upgrading from v2.7.5 to v2.7.8

`openvpn-v2.7.8-aws.patch` replaces `openvpn-v2.7.5-aws.patch`, which was removed from the repository. The old patch applied to v2.7.8 with line offsets only (`ssl.c` hunks shifted by 55 lines, `options.h` needed fuzz 2) and no failed hunks, so no semantic change to the patch was needed. Upstream `ssl.c` changed a lot between the two tags (+206/-84), so the patched `write_string` and key-method code were re-read after applying:

- `write_string` still clamps to `UINT32_MAX` and writes the length with `buf_write_u32()`.
- The key-method buffer still gets `BLEN(buf)` in its first 4 octets.

Upstream also changed `buffer.h` (null-safe `buf_defined()` and `buf_valid()`); this does not touch the patched `BUF_SIZE_MAX` line.

Verification done:

1. `patch -p1 --dry-run` against a fresh v2.7.8 tarball is clean.
2. Default `./configure`, then `make` in `src/compat` and `src/openvpn`, builds with `[DCO]` (`-Wshift-negative-value` warnings from the unparenthesized `BUF_SIZE_MAX` macro remain).
3. The unauthenticated first step of `aws-connect.sh` returns the `AUTH_FAILED,CRV1` challenge with the SAML URL, with both the 2.7.5 and 2.7.8 binaries.

A full authenticated connection with 2.7.8 is the remaining check after the first real reconnect.

## DCO (Data Channel Offload)

DCO builds failed with v2.6.13 on this machine because recent Linux kernel headers define OpenVPN DCO interface values that collided with v2.6.13's bundled DCO compatibility definitions.

OpenVPN v2.7.5 and v2.7.8 built successfully with DCO enabled in this environment. Do not pass `--disable-dco` unless there is a concrete build or runtime issue. Verify DCO support after building with:

```bash
./openvpn --version | grep DCO
```

Expected output should include `[DCO]`.

## Future Upgrade Checklist

1. Check the latest upstream OpenVPN tag.
2. Apply the previous AWS patch with a dry run against the new tag.
3. Inspect and manually resolve failed hunks, especially in `ssl.c` and `manage.c`.
4. Preserve the patch invariants listed above.
5. Build with default `./configure` first so DCO remains enabled when supported.
6. Verify the binary with `./openvpn --version`, including `[DCO]` when expected.
7. Consider parenthesizing macro values such as `(1 << 17)` and `(1 << 18)` if touching the patch, to avoid compiler warnings from macro precedence in expressions like `USER_PASS_LEN - 1`.
