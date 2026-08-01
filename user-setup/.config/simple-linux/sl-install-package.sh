#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

info()    { echo -e "${GREEN}[INFO]${RESET} $*"; }
warning() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# Overridable configuration
: "${HOME:?HOME must be set}"
INSTALL_ROOT="${INSTALL_ROOT:-$HOME}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DB_DIR="${DB_DIR:-$XDG_DATA_HOME/install-package/db}"
DEBUG="${DEBUG:-false}"

# DB record format:
#   version=<pkgver>-<pkgrel>
#   <blank line>
#   relative/path/one
#   relative/path/two
#   ...

db_get_version() {
  local pkg="$1" line
  [ -f "$DB_DIR/$pkg" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      version=*) printf '%s\n' "${line#version=}"; return 0 ;;
      "") return 0 ;;  # blank line before any version= -> treat as no version
    esac
  done < "$DB_DIR/$pkg"
}

db_get_files() {
  local pkg="$1" line in_files=0
  [ -f "$DB_DIR/$pkg" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_files" -eq 1 ]; then
      [ -n "$line" ] && printf '%s\n' "$line"
    elif [ -z "$line" ]; then
      in_files=1
    fi
  done < "$DB_DIR/$pkg"
}

db_set() {
  local pkg="$1" version="$2" manifest="$3"
  mkdir -p "$DB_DIR"
  {
    printf 'version=%s\n\n' "$version"
    [ -n "$manifest" ] && [ -f "$manifest" ] && cat "$manifest"
  } > "$DB_DIR/$pkg"
}

db_remove() {
  local pkg="$1"
  rm -f "$DB_DIR/$pkg"
}

is_archive() {
  case "$1" in
    *.tar.bz2|*.tar.gz|*.tar.xz|*.bz2|*.rar|*.gz|*.tar|*.tbz2|*.tgz|*.zip|*.Z|*.7z) return 0 ;;
    *) return 1 ;;
  esac
}

extract() {
  local archive="$1" dest="${2:-.}"
  if [ ! -f "$archive" ]; then
    error "'$archive' is not a valid file!"
    return 1
  fi
  mkdir -p "$dest"
  case $archive in
    *.tar.bz2|*.tbz2) tar xjf "$archive" -C "$dest" ;;
    *.tar.gz|*.tgz)   tar xzf "$archive" -C "$dest" ;;
    *.tar.xz)         tar xJf "$archive" -C "$dest" ;;
    *.tar)            tar xf "$archive" -C "$dest" ;;
    *.zip)            unzip -q "$archive" -d "$dest" ;;
    *.rar)            rar x "$archive" "$dest/" ;;
    *.7z)             7z x "$archive" "-o$dest" ;;
    *.bz2)            cp -- "$archive" "$dest/" && bunzip2 "$dest/$(basename "$archive")" ;;
    *.gz)             cp -- "$archive" "$dest/" && gunzip "$dest/$(basename "$archive")" ;;
    *.Z)              cp -- "$archive" "$dest/" && uncompress "$dest/$(basename "$archive")" ;;
    *) error "Don't know how to extract '$archive'"; return 1 ;;
  esac
}

contains_variable() {
  local config_path="$1"
  shift
  for var in "$@"; do
    grep -qE "^${var}[=(]" "$config_path" || {
      error "Variable '$var' is required in $config_path"
      return 1
    }
  done
}

# Derive the local filename for a source entry. For 'name::url' the name is
# used verbatim; for a bare url the URL basename is used. The result must be a
# flat filename (no '/'), since all sources are staged directly in $srcdir.
source_filename() {
  local entry="$1" filename
  if [[ "$entry" == *::* ]]; then
    filename="${entry%%::*}"
  else
    filename=$(basename "${entry%%::*}")
  fi
  case "$filename" in
    ""|*/*|.|..) error "Invalid source filename '$filename' in entry '$entry'"; return 1 ;;
  esac
  printf '%s\n' "$filename"
}

verify_checksums() {
  if [ "${#source[@]}" -ne "${#sha256sums[@]}" ]; then
    error "Number of sources and checksums don't match"
    return 1
  fi

  for i in "${!source[@]}"; do
    local filename
    filename=$(source_filename "${source[$i]}") || return 1

    info "Verifying checksum for $filename..."
    echo "${sha256sums[$i]}  $filename" | sha256sum -c - || {
      error "Checksum verification failed for $filename"
      return 1
    }
  done
}

download_sources() {
  for entry in "${source[@]}"; do
    local filename url
    filename=$(source_filename "$entry") || return 1
    if [[ "$entry" == *::* ]]; then
      url="${entry##*::}"
    else
      url="$entry"
    fi

    if [ -f "$filename" ]; then
      info "Source '$filename' already exists, skipping download"
    else
      info "Downloading $filename..."
      curl -fsSL -o "$filename" "$url" || {
        error "Failed to download $url"
        return 1
      }
    fi
  done
}

# Verify dependencies are installed via pacman. Simple presence check only,
# nothing is installed by this script.
check_dependencies() {
  local dep
  for dep in "${depends[@]}"; do
    [ -n "$dep" ] || continue
    pacman -Qq "$dep" &>/dev/null || {
      error "Dependency '$dep' is not installed. Install it first with: sudo pacman -S $dep"
      exit 1
    }
  done
}

install_cmd() {
  declare -f package > /dev/null || {
    error "package() function not found in $FILE"
    exit 1
  }

  local current="${pkgver:?}-${pkgrel:?}"
  local recorded
  recorded="$(db_get_version "${pkgname:?}")"

  if [ -n "$recorded" ] && [ "$recorded" = "$current" ] && [ "$FORCE" -eq 0 ]; then
    info "Package '$pkgname' $current is already installed, skipping (use --force to reinstall)"
    return 0
  fi

  if [ -n "$recorded" ] && [ "$recorded" != "$current" ]; then
    info "Package '$pkgname' changing version: $recorded -> $current"
  fi

  check_dependencies

  cd "$srcdir"

  download_sources
  verify_checksums

  info "Extracting sources..."
  for entry in "${source[@]}"; do
    local filename
    filename=$(source_filename "$entry") || return 1
    if is_archive "$filename"; then
      extract "$srcdir/$filename" "$srcdir"
    else
      info "Source '$filename' is not an archive, staging as-is"
    fi
  done

  if declare -f build > /dev/null; then
    info "Running build()..."
    build
  fi

  info "Running package()..."
  package

  if declare -f clean > /dev/null; then
    info "Running clean()..."
    clean
  fi

  local manifest
  manifest="$WORK_DIR/manifest"
  build_manifest_from_pkgdir "$manifest" || return 1

  if [ ! -s "$manifest" ]; then
    warning "package() produced no files in \$pkgdir, aborting install"
    return 1
  fi

  abort_on_file_conflicts "$manifest" || return 1
  remove_orphaned_files_on_version_change "$manifest"
  install_staged_tree

  db_set "$pkgname" "$current" "$manifest"
  info "Package '$pkgname' installed successfully!"
}

# Build manifest of staged files (relative to $pkgdir). Collected
# null-delimited from find, then validated: the DB format is newline-
# delimited, so a path containing a newline is rejected rather than
# silently corrupting the record. Traversal/absolute paths are rejected
# so uninstall can never rm outside $INSTALL_ROOT.
build_manifest_from_pkgdir() {
  local manifest="$1" rel
  : > "$manifest"
  while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    case "$rel" in
      ""|/*|*$'\n'*) error "Refusing unsupported staged path: '$rel'"; return 1 ;;
      ..|../*|*/../*|*/..) error "Refusing path traversal in staged path: '$rel'"; return 1 ;;
    esac
    printf '%s\n' "$rel" >> "$manifest"
  done < <(cd "$pkgdir" && find . \( -type f -o -type l \) -print0)
}

# File-conflict detection: refuse to clobber a file owned by a *different*
# package, so uninstalling one package can't delete another's files. The
# ownership index is built once (one parse per DB record) into an associative
# array, then each manifest path is checked with an O(1) lookup, avoiding the
# previous O(files * packages) re-parse-and-grep hot loop.
abort_on_file_conflicts() {
  local manifest="$1"
  [ -d "$DB_DIR" ] || return 0
  local conflict=0 other otherpkg owned_path rel
  declare -A owner=()
  for other in "$DB_DIR"/*; do
    [ -f "$other" ] || continue
    otherpkg="$(basename "$other")"
    [ "$otherpkg" = "$pkgname" ] && continue
    while IFS= read -r owned_path; do
      [ -n "$owned_path" ] || continue
      owner["$owned_path"]="$otherpkg"
    done < <(db_get_files "$otherpkg")
  done
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ -n "${owner[$rel]+x}" ]; then
      error "File conflict: '$rel' is already owned by package '${owner[$rel]}'"
      conflict=1
    fi
  done < "$manifest"
  [ "$conflict" -eq 0 ] || { error "Aborting due to file conflicts"; return 1; }
}

# Version-change cleanup: remove files present in the old manifest but no
# longer in the new one, to avoid orphaned files on upgrade/reinstall. The
# new manifest is indexed once into an associative array so each old path is
# tested with an O(1) lookup instead of a per-file grep over the manifest.
remove_orphaned_files_on_version_change() {
  local manifest="$1"
  [ -f "$DB_DIR/$pkgname" ] || return 0
  local old new_path
  declare -A in_manifest=()
  while IFS= read -r new_path; do
    [ -n "$new_path" ] || continue
    in_manifest["$new_path"]=1
  done < "$manifest"
  while IFS= read -r old; do
    [ -n "$old" ] || continue
    if [ -z "${in_manifest[$old]+x}" ]; then
      rm -f "$INSTALL_ROOT/$old"
    fi
  done < <(db_get_files "$pkgname")
}

# Install staged tree into $HOME, overwriting any existing files (matching
# standard package-manager behavior).
install_staged_tree() {
  info "Installing files into \$HOME..."
  cp -a "$pkgdir/." "$INSTALL_ROOT/"
}

uninstall_cmd() {
  local files
  files="$(db_get_files "$pkgname")"

  if [ -z "$files" ]; then
    error "Package '$pkgname' not installed, or has no recorded manifest"
    exit 1
  fi

  info "Removing tracked files..."
  local rel dirs="" dir
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    rm -f "$INSTALL_ROOT/$rel"
    dir="$(dirname "$rel")"
    [ "$dir" = "." ] && continue
    dirs="$dirs"$'\n'"$dir"
  done <<< "$files"

  prune_empty_directories "$dirs"

  db_remove "$pkgname"
  info "Package '$pkgname' uninstalled successfully!"
}

# Prune now-empty directories bottom-up. Sort by depth (longest path first)
# so children are removed before parents. rmdir is non-recursive and only
# removes empty dirs, so unrelated content is preserved.
prune_empty_directories() {
  local dirs="$1" dir
  [ -n "$dirs" ] || return 0
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
      rmdir "$INSTALL_ROOT/$dir" 2>/dev/null || break
      dir="$(dirname "$dir")"
    done
  done < <(printf '%s\n' "$dirs" | awk 'NF' | awk '{ print gsub(/\//,"/"), $0 }' | sort -rn | cut -d' ' -f2-)
}

list_cmd() {
  if [ ! -d "$DB_DIR" ] || [ -z "$(ls -A "$DB_DIR" 2>/dev/null)" ]; then
    info "No packages installed"
    return 0
  fi

  local f pkg version count
  printf '%-24s %-16s %s\n' "PACKAGE" "VERSION" "FILES"
  for f in "$DB_DIR"/*; do
    [ -f "$f" ] || continue
    pkg="$(basename "$f")"
    version="$(db_get_version "$pkg")"
    count="$(db_get_files "$pkg" | wc -l)"
    printf '%-24s %-16s %s\n' "$pkg" "${version:-?}" "$count"
  done
}

cleanup() {
  info "Cleaning up work directory..."
  rm -rf "$WORK_DIR"
}

source_package_file() {
  [ -z "$FILE" ] && usage
  [ -f "$FILE" ] || { error "Package file '$FILE' not found"; exit 1; }
  contains_variable "$FILE" pkgname pkgver source sha256sums pkgrel
  source "$FILE"

  # Ensure source/sha256sums/depends are arrays so "${arr[@]}" is safe under
  # set -u even when a package file leaves them unset or declares them as
  # scalars.
  if ! declare -p source >/dev/null 2>&1 || [[ "$(declare -p source 2>/dev/null)" != "declare -a"* ]]; then
    declare -ga source=()
  fi
  if ! declare -p sha256sums >/dev/null 2>&1 || [[ "$(declare -p sha256sums 2>/dev/null)" != "declare -a"* ]]; then
    declare -ga sha256sums=()
  fi
  if ! declare -p depends >/dev/null 2>&1 || [[ "$(declare -p depends 2>/dev/null)" != "declare -a"* ]]; then
    declare -ga depends=()
  fi

  # Validate pkgname: it becomes a DB filename, so reject path separators and
  # traversal to keep it confined to $DB_DIR.
  case "$pkgname" in
    ""|*/*|.|..) error "Invalid pkgname '$pkgname'"; exit 1 ;;
  esac
}

prepare_package_env() {
  WORK_DIR="$(mktemp -d)"
  srcdir="$WORK_DIR/src"
  pkgdir="$WORK_DIR/pkg"
  mkdir -p "$srcdir" "$pkgdir"
  export srcdir pkgdir
}

usage() {
  echo "Usage: $0 [install|uninstall] <package-file> [--force]"
  echo "       $0 [install|uninstall] --file|-F <package-file> [--force]"
  echo "       $0 list   (or: $0 --list)"
  echo
  echo "PKGBUILD convention: package() installs into \$pkgdir using \$HOME-relative"
  echo "subpaths, e.g. \${pkgdir}/.local/bin/foo, \${pkgdir}/.local/share/icons/bar."
  echo "The staged tree is copied into \$HOME and tracked for automatic uninstall."
  exit 1
}

FORCE=0
FILE=""
ACTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force|-f)
      FORCE=1
      ;;
    --file|-F)
      [ $# -ge 2 ] || { error "Option '$1' requires an argument"; usage; }
      FILE="$2"
      shift
      ;;
    install|uninstall|list)
      ACTION="$1"
      ;;
    -*)
      error "Unknown option '$1'"
      usage
      ;;
    *)
      [ -z "$FILE" ] || { error "Unexpected argument '$1'"; usage; }
      FILE="$1"
      ;;
  esac
  shift
done

case "$ACTION" in
  install|uninstall)
    source_package_file
    prepare_package_env
    trap cleanup EXIT
    "${ACTION}_cmd"
    ;;
  list)
    list_cmd
    ;;
  *)
    error "Unknown action '$ACTION'"
    usage
    ;;
esac