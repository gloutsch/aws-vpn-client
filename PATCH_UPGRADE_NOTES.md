# Patch Upgrade Notes

When upgrading the AWS OpenVPN patch to newer versions, please note the following changes and adaptations that were required historically:

## Upgrading from v2.6.13 to v2.7.5

During the upgrade to v2.7.5, the following upstream changes required adaptations in the AWS patch (`openvpn-v2.7.5-aws.patch`):

1. **`manage.c` (Type Changes):**
   Upstream updated the socket `len` variable from `int` to `ssize_t` to be more compliant with standard network APIs. The patch context had to be updated to match the new `ssize_t len = 0;` line.

2. **`ssl.c` (Buffer Logic Update in `write_string`):**
   In v2.7.5, OpenVPN refactored how `write_string()` handles buffer writes by strictly clamping string limits using `UINT16_MAX` and explicitly casting parameters to `(uint16_t)len`. 
   To accommodate the larger authentication payloads expected by the AWS Client VPN service, the patch now replaces the upstream `UINT16_MAX` limits with `UINT32_MAX`, and updates the buffer write function calls to `buf_write_u32()` along with `(uint32_t)` casts (instead of the upstream `buf_write_u16`).

3. **Line Offsets:**
   Line numbers naturally shifted across almost all patched files.

## DCO (Data Channel Offload) Note
DCO builds failed with `v2.6.13` due to Linux kernel header conflicts (`if_link.h` vs the bundled `ovpn_dco_linux.h`). However, starting with `v2.7.5`, OpenVPN developers resolved these conflicts. DCO can now be safely enabled and compiled by default on modern Linux kernels without any additional patching.
