#!/bin/sh

# -- Functions -----------------------------------------------------------------

print_info() {
  printf '%s\n' "$@"
  log emit --public --subsystem ift --type info "${@}"
}

print_error() {
  printf >&2 '\033[31;1;4m%s\033[0m' "$@"
  log emit --public --subsystem ift --type error "${@}"
}

exit_error() {
  print_error "${@}"
  exit 1
}

get_wine_app() {
  if mdfind "kMDItemKind == 'Application'" | grep -q CrossOver; then
    wine_app=CrossOver
  elif mdfind "kMDItemKind == 'Application'" | grep -q 'Wine Stable'; then
    wine_app='Wine Stable'
  fi
  printf "%s" "${wine_app}"
}

init() {
  smb_path="$1"
  print_info "Mount SMB volume"
  message="$(osascript -e "mount volume \"${smb_path}\"" 2>&1 >/dev/null)"
  # shellcheck disable=SC2181
  if [ "${?}" -ne 0 ]; then
    error_message="Unable to mount SMB volume: ${message}"
    exit_error "${error_message}"
  fi

}

iftool() {
  iftool_path="$1"

  wine_app="$(get_wine_app)"
  print_info "Open IFTool"
  open -jga "${wine_app}" "${iftool_path}"

  if [ "${wine_app}" = "CrossOver" ]; then
    # Hide CrossOver window
    osascript -e '
	tell application "System Events"
		set visible of application process "CrossOver" to false
	end tell'
    ift_tool_process='IFT_Tool.exe'
  else
    ift_tool_process='wine64-preloader'
  fi

  print_info "Wait until IFTool is ready…"
  while ! pgrep -lq "${ift_tool_process}"; do
    sleep 1
  done

  print_info "Wait until IFTool is closed…"
  while pgrep -lq "${ift_tool_process}"; do
    sleep 1
  done
}

cleanup() {
  iftool_mountpoint="$1"

  error="$(diskutil unmount "${iftool_mountpoint}" 2>&1 >/dev/null)"
  # shellcheck disable=SC2181
  if [ "$?" -ne 0 ]; then
    print_error "${error}"
  fi

  killall "$(get_wine_app || true)"
}

main() {
  iftool_directory_prefix='30_IT'
  iftool_directory='01_IFT_Tool'
  smb_path="smb://data.ift.tuwien.ac.at/${iftool_directory_prefix}"
  iftool_mountpoint="/Volumes/${iftool_directory_prefix}"
  iftool_path="${iftool_mountpoint}/${iftool_directory}/IFT_Tool.exe"

  init "${smb_path}"
  trap 'cleanup '"${iftool_mountpoint}" ABRT EXIT INT QUIT
  iftool "${iftool_path}"
}

# -- Main ----------------------------------------------------------------------

main
