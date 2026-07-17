# Patch Upgrade Notes

This repository carries a small AWS Client VPN compatibility patch on top of upstream OpenVPN. When upgrading OpenVPN, keep the patch semantics intact and only adapt the surrounding context to upstream code changes.

## Patch Invariants

The AWS patch is intended to preserve these behaviours:

1. Increase buffer and option sizes so large AWS SAML authentication payloads can pass through OpenVPN.
2. Use 32-bit string length fields in the TLS key method payload instead of upstream 16-bit fields.
3. Write the key-method payload length into the first 4 octets of the buffer before sending it.
4. Increase management socket and command-line buffers so the larger auth payload is not truncated.

## Upgrading from v2.6.13 to v2.7.5

During the upgrade to v2.7.5, the following upstream changes required adaptations in `openvpn-v2.7.5-aws.patch`:

1. **`manage.c` (Type Changes):**
   Upstream updated the socket `len` variable from `int` to `ssize_t` to be more compliant with standard network APIs. The patch context had to be updated to match the new `ssize_t len = 0;` line.

2. **`ssl.c` (`write_string` Length Handling):**
   Upstream v2.7.5 now clamps string lengths with `UINT16_MAX` and explicitly casts to `(uint16_t)len` before calling `buf_write_u16()`. The AWS compatibility patch must keep the 32-bit length semantics, so this was adapted to `UINT32_MAX`, `(uint32_t)len`, and `buf_write_u32()`.

3. **`ssl.c` (Key Method Length Prefix):**
   The existing AWS behaviour that writes `BLEN(buf)` into the first 4 octets of the key-method buffer is still required and was retained.

## DCO (Data Channel Offload)

DCO builds failed with v2.6.13 on this machine because recent Linux kernel headers define OpenVPN DCO interface values that collided with v2.6.13's bundled DCO compatibility definitions.

OpenVPN v2.7.5 built successfully with DCO enabled in this environment. Do not pass `--disable-dco` unless there is a concrete build or runtime issue. Verify DCO support after building with:

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
