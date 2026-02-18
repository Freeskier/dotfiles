#!/usr/bin/env bash
#
# Check for official and AUR package updates and upgrade them. When run with the
# "module" argument, output the status icon and update counts in JSON format for
# Waybar
#
# Requirements:
# - checkupdates (pacman-contrib)
# - notify-send (libnotify)
# - Optional: An AUR helper
#
# Author:  Jesse Mirabel <sejjymvm@gmail.com>
# Date:    August 16, 2025
# License: MIT

FG_GREEN="\e[32m"
FG_BLUE="\e[34m"
FG_RESET="\e[39m"

FAILURE=false
PAC_UPD=0
AUR_UPD=0

TIMEOUT=10
HELPERS=(aura paru pikaur trizen yay)

printf() {
	command printf "$@" >&2
}

get_helper() {
	local helper
	for helper in "${HELPERS[@]}"; do
		if command -v "$helper" > /dev/null; then
			HELPER=$helper
			break
		fi
	done
}

check_updates() {
	local pac_output pac_status

	pac_output=$(timeout $TIMEOUT checkupdates)
	pac_status=$?

	if ((pac_status != 0 && pac_status != 2)); then
		FAILURE=true
		return 1
	fi

	PAC_UPD=$(grep -c . <<< "$pac_output")

	if [[ -z $HELPER ]]; then
		return 0
	fi

	local aur_output aur_status

	aur_output=$(timeout $TIMEOUT "$HELPER" -Quaq)
	aur_status=$?

	if ((${#aur_output} > 0 && aur_status != 0)); then
		FAILURE=true
		return 1
	fi

	AUR_UPD=$(grep -c . <<< "$aur_output")
}

update_packages() {
	local failed=false

	printf "%bUpdating pacman packages...%b\n" "$FG_BLUE" "$FG_RESET"
	if ! sudo pacman -Syu; then
		failed=true
	fi

	if [[ -n $HELPER && $failed == false ]]; then
		printf "\n%bUpdating AUR packages...%b\n" "$FG_BLUE" "$FG_RESET"
		if ! command "$HELPER" -Syu; then
			failed=true
		fi
	fi

	if [[ $failed == true ]]; then
		notify-send "Update failed" -u critical -i "package-purge"
		printf "\nUpdate failed.\n"
		read -rsn 1 -p "Press any key to exit..."
		return 1
	fi

	notify-send "Update complete" -i "package-install"

	printf "\n%bUpdate Complete!%b\n" "$FG_GREEN" "$FG_RESET"
	read -rsn 1 -p "Press any key to exit..."
}

display_module() {
	if $FAILURE; then
		command printf "{ \"text\": \"󰒑\", \"tooltip\": \"Cannot fetch updates. Right-click to retry.\" }\n"
		exit 0
	fi

	local tooltip="<b>Official</b>: $PAC_UPD"

	if [[ -n $HELPER ]]; then
		tooltip+="\n<b>AUR($HELPER)</b>: $AUR_UPD"
	fi

	if ((PAC_UPD + AUR_UPD == 0)); then
		command printf "{ \"text\": \"󰸟\", \"tooltip\": \"No updates available\" }\n"
	else
		command printf "{ \"text\": \"󰄠\", \"tooltip\": \"%s\" }\n" "$tooltip"
	fi
}

main() {
	get_helper

	case $1 in
		module)
			check_updates
			display_module
			;;
		*)
			printf "%bChecking for updates...%b\n" "$FG_BLUE" "$FG_RESET"
			if ! check_updates; then
				notify-send "Update check failed" -u critical -i "package-purge"
				printf "Cannot fetch updates.\n"
				return 1
			fi
			if ! update_packages; then
				return 1
			fi

			# update the module
			pkill -RTMIN+1 waybar
			;;
	esac
}

main "$@"
