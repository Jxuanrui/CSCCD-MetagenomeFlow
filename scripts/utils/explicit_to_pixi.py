#!/usr/bin/env python3
"""Convert a conda @EXPLICIT manifest into a fully-pinned pixi.toml.

Every package from the manifest (not just the main tool) is emitted with
name + version + build pinned, per review standard P0-1.

Usage:
    python3 scripts/utils/explicit_to_pixi.py <manifest.txt> [--output <pixi.toml>]

    <manifest.txt>      conda `conda env export --explicit` style file:
                        comment header, `@EXPLICIT` marker, one package URL
                        per line. Env name is taken from the file stem
                        (fastp.txt -> name = "fastp").
    --output <path>     Write pixi.toml to <path> instead of stdout.
                        The summary always goes to stderr, so stdout stays
                        clean TOML when piping.

URL parsing (conda filename rules, applied right-to-left):
    .../<platform>/<name>-<version>-<build>.<conda|tar.bz2>
    The package NAME may contain hyphens; version and build may not, so we
    split from the right: last '-'-segment = build, second-to-last = version,
    everything before = name.

Channel extraction:
    https://conda.anaconda.org/<channel>/...          -> <channel>
    https://repo.anaconda.com/pkgs/<channel>/...      -> pkgs/<channel>
    https://repo.anaconda.com/main/...                -> defaults
Note: "pkgs/main" / "defaults" name repo.anaconda.com channels. pixi cannot
resolve those shorthands by itself; if pixi refuses to solve, rewrite them in
the generated file as https://repo.anaconda.com/pkgs/main etc.

Behavior:
    - Packages deduplicated on (name, version, build); the same package name
      with conflicting pins is kept as first occurrence and warned on stderr.
    - noarch packages are accepted and counted, but do not widen
      [project].platforms (which comes from the `# platform:` header comment,
      else the non-noarch platforms seen in URLs).
    - Malformed URLs are skipped with a stderr warning and counted.
    - Empty manifest -> minimal template plus a WARNING comment.
"""

import argparse
import re
import sys
from pathlib import Path

# Conda explicit files may append "#<md5>" to URLs; strip before matching.
_CONDA_ORG_RE = re.compile(
    r"^https?://conda\.anaconda\.org/([^/]+)/([^/]+)/([^/#?]+)$")
_REPO_PKGS_RE = re.compile(
    r"^https?://repo\.anaconda\.com/pkgs/([^/]+)/([^/]+)/([^/#?]+)$")
_REPO_MAIN_RE = re.compile(
    r"^https?://repo\.anaconda\.com/main/([^/]+)/([^/#?]+)$")
_PLATFORM_COMMENT_RE = re.compile(r"^#\s*platform:\s*(\S+)\s*$", re.MULTILINE)

_EXTENSIONS = (".conda", ".tar.bz2")

# The repo's primary channel (§2 channel discipline); packages from it do not
# need an explicit per-package `channel` key.
_DEFAULT_CHANNEL = "conda-forge"

# Fallback platform if a manifest contains no platform information at all.
_FALLBACK_PLATFORM = "linux-64"

_TOML_BARE_KEY_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def toml_string(value):
    """Escape a python str as a TOML basic string."""
    out = value.replace("\\", "\\\\").replace('"', '\\"')
    return '"%s"' % out


def toml_key(name):
    """Quote a key only when it is not a valid TOML bare key."""
    if _TOML_BARE_KEY_RE.match(name):
        return name
    return toml_string(name)


def parse_filename(filename):
    """Split '<name>-<version>-<build>.<ext>' -> (name, version, build).

    Name may contain hyphens; parse from the right. Returns None when the
    stem does not have all three components, the extension is unknown, or
    the version field does not start with a digit (conda versions always
    do; this rejects malformed stems like 'no-build-string.conda' that
    would otherwise split into plausible-looking garbage).
    """
    for ext in _EXTENSIONS:
        if filename.endswith(ext):
            stem = filename[: -len(ext)]
            break
    else:
        return None
    parts = stem.rsplit("-", 2)
    if len(parts) != 3 or not all(parts):
        return None
    name, version, build = parts
    if not version[0].isdigit():
        return None
    return name, version, build


def parse_url(url):
    """Parse one manifest URL -> (channel, platform, name, version, build).

    Returns None (with reason) when the URL matches no known layout or the
    filename cannot be split into name/version/build.
    """
    for regex, kind in ((_CONDA_ORG_RE, "org"), (_REPO_PKGS_RE, "pkgs"),
                        (_REPO_MAIN_RE, "main")):
        match = regex.match(url.split("#", 1)[0])
        if match:
            break
    else:
        return None, "unrecognized channel/URL layout"

    if kind == "org":
        channel, platform, filename = match.groups()
    elif kind == "pkgs":
        channel, platform, filename = match.groups()
        channel = "pkgs/%s" % channel
    else:
        platform, filename = match.groups()
        channel = "defaults"

    parsed = parse_filename(filename)
    if parsed is None:
        return None, "cannot split filename into name-version-build"
    name, version, build = parsed
    return (channel, platform, name, version, build), None


def read_manifest(path):
    """Return (env_name, platform_hint, url_lines, saw_explicit_marker)."""
    text = Path(path).read_text(encoding="utf-8")
    env_name = Path(path).stem

    platform_match = _PLATFORM_COMMENT_RE.search(text)
    platform_hint = platform_match.group(1) if platform_match else None

    urls = []
    saw_marker = False
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.upper() == "@EXPLICIT":
            saw_marker = True
            continue
        if line.startswith(("http://", "https://")):
            urls.append(line)
        else:
            print("WARNING: skipping non-URL line: %s" % raw_line,
                  file=sys.stderr)
    return env_name, platform_hint, urls, saw_marker


def convert(manifest_path):
    """Parse the manifest and return (pixi_toml_text, stats_dict)."""
    env_name, platform_hint, urls, saw_marker = read_manifest(manifest_path)

    if not saw_marker:
        print("WARNING: no @EXPLICIT marker found in %s; parsed URL lines "
              "anyway" % manifest_path, file=sys.stderr)

    packages = []          # ordered unique (channel, platform, name, ver, build)
    seen_pins = set()      # (name, version, build) already emitted
    pins_by_name = {}      # name -> (version, build) first kept
    channels = []          # unique, order of first appearance
    platforms = []         # unique non-noarch, order of first appearance
    malformed = []
    exact_dups = 0
    conflicts = 0

    for url in urls:
        parsed, reason = parse_url(url)
        if parsed is None:
            malformed.append((url, reason))
            continue
        channel, platform, name, version, build = parsed
        if channel not in channels:
            channels.append(channel)
        if platform != "noarch" and platform not in platforms:
            platforms.append(platform)

        pin = (name, version, build)
        if pin in seen_pins:
            exact_dups += 1
            continue
        seen_pins.add(pin)

        if name in pins_by_name:
            conflicts += 1
            kept_version, kept_build = pins_by_name[name]
            print("WARNING: duplicate package name %r with conflicting pin; "
                  "keeping %s-%s-%s, ignoring %s-%s-%s"
                  % (name, name, kept_version, kept_build, name, version,
                     build), file=sys.stderr)
            continue
        pins_by_name[name] = (version, build)
        packages.append((channel, platform, name, version, build))

    if not platform_hint and not platforms:
        print("WARNING: no platform information found; defaulting "
              "platforms to [%r]" % _FALLBACK_PLATFORM, file=sys.stderr)
    project_platforms = ([platform_hint] if platform_hint else platforms) \
        or [_FALLBACK_PLATFORM]

    stats = {
        "urls": len(urls),
        "packages": len(packages),
        "exact_dups": exact_dups,
        "conflicts": conflicts,
        "malformed": len(malformed),
        "channels": channels,
        "platforms": project_platforms,
    }
    return render_toml(env_name, manifest_path, channels, project_platforms,
                       packages, bool(malformed)), stats


def render_toml(env_name, source_path, channels, platforms, packages, empty):
    """Render the final pixi.toml text."""
    lines = [
        "# AUTO-GENERATED from @EXPLICIT manifest by explicit_to_pixi.py",
        "# Source: %s" % source_path,
        "# ALL packages pinned to name+version+build (review P0-1 "
        "standard)",
        "# NOTE: channels named pkgs/* or 'defaults' are repo.anaconda.com "
        "channels; rewrite them to full",
        "#       https://repo.anaconda.com/... URLs if pixi cannot resolve "
        "them.",
        "",
        "[project]",
        "name = %s" % toml_string(env_name),
        "channels = [%s]" % ", ".join(toml_string(c) for c in channels),
        "platforms = [%s]" % ", ".join(toml_string(p) for p in platforms),
        "",
        "[dependencies]",
    ]
    if not packages:
        lines.append("# WARNING: manifest contained no packages; nothing "
                     "to pin.")
    for channel, _platform, name, version, build in packages:
        parts = ["version = %s" % toml_string("==%s" % version),
                 "build = %s" % toml_string(build)]
        if channel != _DEFAULT_CHANNEL:
            parts.append("channel = %s" % toml_string(channel))
        lines.append("%s = { %s }" % (toml_key(name), ", ".join(parts)))
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Convert a conda @EXPLICIT manifest into a "
                    "fully-pinned pixi.toml (name+version+build for every "
                    "package).")
    parser.add_argument("manifest", help="path to the @EXPLICIT .txt file")
    parser.add_argument("--output", "-o", default=None,
                        help="write pixi.toml here instead of stdout")
    args = parser.parse_args(argv)

    manifest_path = Path(args.manifest)
    if not manifest_path.is_file():
        parser.error("manifest not found: %s" % manifest_path)

    toml_text, stats = convert(manifest_path)

    if args.output:
        Path(args.output).write_text(toml_text, encoding="utf-8")
    else:
        sys.stdout.write(toml_text)

    print("Summary: %d URL(s) -> %d pinned package(s) | exact duplicates "
          "removed: %d | name conflicts ignored: %d | malformed skipped: %d "
          "| channels: %s | platforms: %s"
          % (stats["urls"], stats["packages"], stats["exact_dups"],
             stats["conflicts"], stats["malformed"],
             ", ".join(stats["channels"]),
             ", ".join(stats["platforms"])), file=sys.stderr)
    if not stats["urls"]:
        print("WARNING: manifest is empty (header only); generated a "
              "minimal template", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
