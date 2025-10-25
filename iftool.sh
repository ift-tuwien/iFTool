#!/bin/sh

# -- Functions -----------------------------------------------------------------

print_info() {
	printf '⚙️ %s' "$@"
}

exit_error() {
	printf >&2 '😱 \033[31;1;4m%s\033[0m' "$@"
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
	vpn="$1"
	smb_path="$2"
	internal_ip_regex="^(128\.130\.106|128\.131)"

	print_info "Determine external IP\n"
	external_ips="$(curl ifconfig.me)"
	print_info "External IPs:\n%s\n" "${external_ips}"
	if ! printf '%s' "${external_ips}" | grep -Eq "${internal_ip_regex}"; then
		print_info 'Connect to VPN “%s”\n' "${vpn}"
		networksetup -connectpppoeservice "${vpn}"
		timeout=10
		time_left="${timeout}"
		while ! scutil --nc list | grep "${vpn}" | grep -q Connected; do
			if [ "${time_left}" -lt 1 ]; then
				exit_error \
					'Unable to connect to VPN “'"${vpn}"'” in '"${timeout}"' seconds'
			fi
			sleep 1
			time_left=$((time_left - 1))
		done
	fi
	print_info "Mount SMB volume\n"
	message="$(osascript -e "mount volume \"${smb_path}\"" 2>&1 > /dev/null)"
	# shellcheck disable=SC2181
	if [ "$?" -ne 0 ]; then
		error_message="Unable to mount SMB volume: ${message}\n"
		exit_error "${error_message}"
	fi

}

iftool() {
	iftool_path="$1"

	wine_app="$(get_wine_app)"
	print_info "Open IFTool\n"
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

	print_info "Wait until IFTool is ready…\n"
	while ! pgrep -lq "${ift_tool_process}"; do
		sleep 1
	done

	print_info "Wait until IFTool is closed…\n"
	while pgrep -lq "${ift_tool_process}"; do
		sleep 1
	done
}

cleanup() {
	vpn="$1"
	iftool_mountpoint="$2"

	diskutil unmount "${iftool_mountpoint}" > /dev/null
	networksetup -disconnectpppoeservice "${vpn}"

	killall "$(get_wine_app || true)"
}

main() {
	vpn='TU Vienna'

	iftool_directory_prefix='30_IT'
	iftool_directory='01_IFT_Tool'
	smb_path="smb://data.ift.tuwien.ac.at/${iftool_directory_prefix}"
	iftool_mountpoint="/Volumes/${iftool_directory_prefix}"
	iftool_path="${iftool_mountpoint}/${iftool_directory}/IFT_Tool.exe"

	init "${vpn}" "${smb_path}"
	iftool "${iftool_path}"
	cleanup "${vpn}" "${iftool_mountpoint}"
}

# -- Main ----------------------------------------------------------------------

main
