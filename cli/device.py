"""Device detection helpers for the CLI."""

from __future__ import annotations

import logging
from pathlib import Path

from ipod_device.scanner import scan_for_ipods
from ipod_device.info import DeviceInfo

logger = logging.getLogger(__name__)


def find_ipod(mount_hint: str | None = None) -> tuple[DeviceInfo, str] | None:
    """Return (DeviceInfo, itunesdb_path) for the first found iPod.

    If *mount_hint* is given, only that mount path is considered.
    Returns None when no iPod is found.
    """
    if mount_hint:
        db_path = _itunesdb_path(mount_hint)
        if not Path(db_path).exists():
            logger.error("No iTunesDB found at %s", db_path)
            return None
        # Try to get full DeviceInfo from the scanner (enriches checksum type etc.)
        devices = scan_for_ipods()
        for d in devices:
            if str(d.path) == str(mount_hint):
                return d, db_path
        # Scanner didn't find it (path not in its search dirs) — synthesise minimal info
        from ipod_device.info import DeviceInfo
        info = DeviceInfo()
        info.path = mount_hint
        info.mount_name = Path(mount_hint).name
        logger.info("Using filesystem-only mode for %s", mount_hint)
        return info, db_path

    devices = scan_for_ipods()
    if not devices:
        return None

    device = devices[0]
    if len(devices) > 1:
        logger.info("Multiple iPods found — using first: %s", device.display_name)

    db_path = _itunesdb_path(str(device.path))
    return device, db_path


def _itunesdb_path(mount: str) -> str:
    return str(Path(mount) / "iPod_Control" / "iTunes" / "iTunesDB")
