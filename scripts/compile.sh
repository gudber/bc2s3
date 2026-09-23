#!/usr/bin/env bash
# ABOUTME: Compiles the app and the test app with the AL compiler on macOS/Linux, without Business Central.
# ABOUTME: Fetches Microsoft's symbol packages from the public MSSymbols NuGet feed on first use.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SYMBOLS_VERSION="${SYMBOLS_VERSION:-28.5.54151.54365}"
PLATFORM_VERSION="${PLATFORM_VERSION:-28.0.54265}"
DOTNET="${DOTNET:-$HOME/.local/share/dotnet/dotnet}"
ALC="${ALC:-$HOME/.local/share/al/extension/bin/alc.dll}"
CACHE="${CACHE:-$HOME/.cache/bc2s3/symbols/$SYMBOLS_VERSION}"
OUT="$REPO/.output"
FEED="https://dynamicssmb2.pkgs.visualstudio.com/571e802d-b44b-45fc-bd41-4cfddec73b44/_packaging/b656b10c-3de0-440c-900c-bc2e4e86d84c/nuget/v3/flat2"

PACKAGES=(
  Microsoft.Platform.symbols
  Microsoft.SystemApplication.symbols.63ca2fa4-4f03-4f2b-a480-172fef340d3f
  Microsoft.BusinessFoundation.symbols.f3552374-a1f2-4356-848e-196002525837
  Microsoft.BaseApplication.symbols.437dbf0e-84ff-417a-965d-ed2bb9650972
  Microsoft.Application.symbols
  Microsoft.LibraryAssert.symbols.dd0be2ea-f733-4d65-bb34-a28f4624fb14
  Microsoft.Any.symbols.e7320ebb-08b3-4406-b1ec-b4927d3e280b
  Microsoft.LibraryVariableStorage.symbols.5095f467-0a01-4b99-99d1-9ff1237d286f
  Microsoft.Tests-TestLibraries.symbols.5d86850b-0d76-4eca-bd7b-951ad998e997
  Microsoft.TestRunner.symbols.23de40a6-dfe8-4f80-80db-d70f83ce8caf
  Microsoft.ApplicationTestLibrary.symbols.d852d5d2-a39d-4179-baeb-f99a19e32510
  Microsoft.SystemApplicationTestLibrary.symbols.9856ae4f-d1a7-46ef-89bb-6ef056398228
  Microsoft.PermissionsMock.symbols.40860557-a18d-42ad-aecb-22b7dd80dc80
)

fetch_symbols() {
  mkdir -p "$CACHE"
  local package id version nupkg
  for package in "${PACKAGES[@]}"; do
    id="$(echo "$package" | tr '[:upper:]' '[:lower:]')"
    version="$SYMBOLS_VERSION"
    [[ "$package" == Microsoft.Platform.symbols ]] && version="$PLATFORM_VERSION"
    [[ -e "$CACHE/.$id" ]] && continue
    nupkg="$CACHE/$id.nupkg"
    curl -sSfL "$FEED/$id/$version/$id.$version.nupkg" -o "$nupkg"
    unzip -qoj "$nupkg" '*.app' -d "$CACHE"
    rm "$nupkg"
    touch "$CACHE/.$id"
  done
}

# The test app compiles against the freshly built app, so both share one package folder.
compile() {
  local project="$1"
  "$DOTNET" "$ALC" "/project:$project" "/packagecachepath:$OUT/packages" "/outfolder:$OUT/packages" /errorsonlyinconsole
}

fetch_symbols
rm -rf "$OUT/packages"
mkdir -p "$OUT/packages"
cp "$CACHE"/*.app "$OUT/packages/"
compile "$REPO/businessCentral/app"
compile "$REPO/businessCentral/test"
