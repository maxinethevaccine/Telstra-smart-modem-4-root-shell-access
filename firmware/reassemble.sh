#!/bin/sh
# Reassemble split firmware images
# Run from the firmware/ directory

echo "Reassembling modem_p55.img..."
cat modem_p55.img.part_* > modem_p55.img
echo "Done. Verify with: sha256sum modem_p55.img"

echo ""
echo "To reconstruct system_p57.img from rootfs.squashfs:"
echo "  The rootfs lives at sector offset 38192 (byte offset 19554304) inside system_p57."
echo "  rootfs.squashfs is the usable filesystem — system_p57 is just the raw partition."
