#!/usr/bin/env bash
# Versioning and updates of the server bundle.
# shellcheck shell=bash

RELEASES_API=${RELEASES_API:-https://terraria.org/api/get/dedicated-servers-names}
DOWNLOAD_BASE=${DOWNLOAD_BASE:-https://terraria.org/api/download/pc-dedicated-server}

# terraria.org numbers releases without separators: 1458 → 1.4.5.8.
terraria_release_to_version() {
    printf '%s' "$1" | sed 's/./&./g; s/\.$//'
}

terraria_installed_release() {
    [[ -r "${GAME_DIR}/VERSION" ]] && tr -d '[:space:]' < "${GAME_DIR}/VERSION"
}

# Highest release number in the API's JSON array of zip names.
#   terraria_latest_from_json '["terraria-server-1458.zip","terraria-server-1456.zip"]' → 1458
terraria_latest_from_json() {
    local json=$1 i entry best=""
    for (( i = 0; ; i++ )); do
        entry=$(printf '%s' "$json" | json_get - "[$i]" 2>/dev/null) || break
        [[ "$entry" =~ ^terraria-server-([0-9]+)\.zip$ ]] || continue
        if [[ -z "$best" ]] || (( BASH_REMATCH[1] > best )); then best=${BASH_REMATCH[1]}; fi
    done
    [[ -n "$best" ]] && printf '%s' "$best"
    return 0
}

# Download <release> and replace the installation in place.
terraria_install_release() {
    local release=$1
    local tmp
    tmp=$(mktemp -d)
    log_info "downloading Terraria server ${release}"
    if ! http_get -o "${tmp}/server.zip" "${DOWNLOAD_BASE}/terraria-server-${release}.zip"; then
        rm -rf "$tmp"; log_error "download failed"; return 1
    fi
    if ! unzip -tq "${tmp}/server.zip" >/dev/null; then
        rm -rf "$tmp"; log_error "downloaded archive is corrupt"; return 1
    fi
    if ! unzip -q "${tmp}/server.zip" "${release}/Linux/*" "${release}/Windows/serverconfig.txt" -d "${tmp}/x"; then
        rm -rf "$tmp"; log_error "extract failed"; return 1
    fi
    [[ -f "${tmp}/x/${release}/Linux/TerrariaServer.bin.x86_64" ]] || { rm -rf "$tmp"; log_error "archive has no Linux server"; return 1; }
    find "$GAME_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    cp -a "${tmp}/x/${release}/Linux/." "$GAME_DIR/"
    cp "${tmp}/x/${release}/Windows/serverconfig.txt" "${GAME_DIR}/serverconfig-example.txt" 2>/dev/null || true
    chmod +x "${GAME_DIR}/TerrariaServer" "${GAME_DIR}/TerrariaServer.bin.x86_64"
    printf '%s\n' "$release" > "${GAME_DIR}/VERSION"
    rm -rf "$tmp"
}
