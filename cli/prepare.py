"""Pre-stage music and podcasts for fast iPod sync.

Run `iopod prepare` on a timer so the heavy work -- fingerprinting playlist
tracks and downloading podcast episodes -- is done before the iPod connects.
`iopod sync` then reads the manifest and skips the full-library scan entirely.

Staging layout under cache_dir (default /var/cache/iopod):
  manifest.json          -- fingerprints and playlist membership
  podcasts/<md5>/        -- downloaded episodes keyed by feed URL hash
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
from pathlib import Path

from cli.config import SyncConfig

logger = logging.getLogger(__name__)

DEFAULT_CACHE_DIR = Path("/var/cache/iopod")


def _parse_m3u(path):
    p = Path(path)
    base = p.parent
    results = []
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                fp = Path(line) if os.path.isabs(line) else base / line
                resolved = str(fp.resolve())
                if os.path.isfile(resolved):
                    results.append(resolved)
    except OSError as e:
        logger.error("Cannot read playlist %s: %s", path, e)
    return results


def resolve_playlist_tracks(config):
    result = {}
    for pl in config.playlists:
        tracks = _parse_m3u(pl)
        result[str(pl)] = tracks
        logger.info("Playlist %s: %d tracks", Path(pl).name, len(tracks))
    return result


def _fingerprint(path):
    try:
        from SyncEngine.audio_fingerprint import get_or_compute_fingerprint
        return get_or_compute_fingerprint(path)
    except Exception as e:
        logger.warning("Fingerprint failed for %s: %s", path, e)
        return None


def _save_fingerprint_cache():
    try:
        from SyncEngine.audio_fingerprint import FingerprintCache
        FingerprintCache.get_instance().save()
    except Exception as e:
        logger.warning("Could not save fingerprint cache: %s", e)


def _feed_slug(url):
    return hashlib.md5(url.encode()).hexdigest()[:12]


def _stage_podcast_feed(url, keep, staged_dir, dry_run):
    from PodcastManager.feed_parser import fetch_feed
    from PodcastManager.downloader import download_episode

    feed_dir = staged_dir / _feed_slug(url)
    if not dry_run:
        feed_dir.mkdir(parents=True, exist_ok=True)

    try:
        feed = fetch_feed(url)
    except Exception as e:
        logger.error("Failed to fetch feed %s: %s", url, e)
        return []

    episodes = sorted(feed.episodes, key=lambda e: e.pub_date, reverse=True)[:keep]
    entries = []

    for ep in episodes:
        entry = {
            "guid": ep.guid,
            "title": ep.title,
            "audio_url": ep.audio_url,
            "pub_date": ep.pub_date,
            "staged_path": None,
        }
        if not dry_run and ep.audio_url:
            try:
                dest = download_episode(ep, str(feed_dir))
                entry["staged_path"] = dest
                # download_episode returns existing path if already downloaded
                print(f"  [staged] {ep.title[:70]}")
            except Exception as e:
                logger.error("Download failed for %s: %s", ep.title, e)
        elif dry_run:
            print(f"  [dry-run] would stage: {ep.title[:70]}")
        entries.append(entry)

    return entries


def run_prepare(config, cache_dir=DEFAULT_CACHE_DIR, dry_run=False):
    podcast_staged_dir = cache_dir / "podcasts"
    if not dry_run:
        cache_dir.mkdir(parents=True, exist_ok=True)
        podcast_staged_dir.mkdir(parents=True, exist_ok=True)

    # 1. Resolve playlists to exact track paths (no full-library scan)
    playlist_tracks = resolve_playlist_tracks(config)
    unique_tracks = {}
    for tracks in playlist_tracks.values():
        for t in tracks:
            unique_tracks[t] = None

    total = len(unique_tracks)
    print(f"[Prepare] {total} unique tracks across {len(config.playlists)} playlist(s)")

    # 2. Fingerprint only playlist tracks, populating the shared cache.
    # `iopod sync` PLAN phase will get cache hits and skip recomputation.
    manifest_music = {}
    path_to_fp = {}

    for i, path in enumerate(unique_tracks, 1):
        print(f"  [fingerprint] [{i}/{total}] {Path(path).name}", flush=True)
        fp = _fingerprint(path)
        if fp is None:
            continue
        path_to_fp[path] = fp
        manifest_music[fp] = {"source_path": path}

    if not dry_run:
        _save_fingerprint_cache()

    print(f"[Prepare] Fingerprinted {len(manifest_music)} tracks")

    # 3. Playlist membership index
    manifest_playlists = {}
    for pl, tracks in playlist_tracks.items():
        manifest_playlists[pl] = [path_to_fp[t] for t in tracks if t in path_to_fp]

    # 4. Download podcast episodes to staging
    manifest_podcasts = {}
    if config.podcasts:
        print(f"\n[Prepare] Podcasts: {len(config.podcasts)} feed(s)")
        for pod in config.podcasts:
            print(f"  {pod.url}")
            entries = _stage_podcast_feed(pod.url, pod.keep_episodes, podcast_staged_dir, dry_run)
            manifest_podcasts[pod.url] = entries

    # 5. Write manifest
    manifest = {
        "music": manifest_music,
        "playlists": manifest_playlists,
        "podcasts": manifest_podcasts,
    }
    manifest_path = cache_dir / "manifest.json"

    if not dry_run:
        manifest_path.write_text(json.dumps(manifest, indent=2))
        print(f"\n[Prepare] Done -- manifest at {manifest_path}")
    else:
        print(f"\n[Prepare] Dry run -- would write manifest to {manifest_path}")

    return True


def load_manifest(cache_dir=DEFAULT_CACHE_DIR):
    manifest_path = cache_dir / "manifest.json"
    if not manifest_path.exists():
        return None
    return json.loads(manifest_path.read_text())
