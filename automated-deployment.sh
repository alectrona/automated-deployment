#!/bin/bash
#shellcheck disable=SC2129

# Alectrona Automated Deployment

# An easy to configure automated deployment workflow for macOS leveraging Jamf Pro and DEPNotify.

# Created by Alectrona for use with https://github.com/alectrona/automated-deployment

# Jamf Pro Parameters
company="$4"                # Company
companyLogoURL="$5"         # Company Logo URL
policyDetailString="$6"     # Policy Detail String
checkOSUpdates="$7"         # Check macOS Updates (true|false)
demoteLoggedInUser="$8"     # Demote Logged-In User (true|false)
dryRun="$9"                 # Run the workflow without making changes (true|false)

# Variables beyond this point are not intended to be modified
scriptName=$(/usr/bin/basename "$0")
companyLogoFilename=${companyLogoURL##*/}
DEPNotifyDownloadURL="https://files.nomad.menu/DEPNotify.pkg"
DEPNotifyPkg=${DEPNotifyDownloadURL##*/}
DEPNotifyApp=/Applications/Utilities/DEPNotify.app
DEPNotifyConfig="/var/tmp/depnotify.log"
osVersion=$(/usr/bin/sw_vers -productVersion)
osMajorVersion=$(/usr/bin/cut -f 1 -d '.' <<< "$osVersion")
osMinorVersion=$(/usr/bin/cut -f 2 -d '.' <<< "$osVersion")
additionalOptsCounter="1"
log="/var/log/alectrona.log"
completionBreadcrumb="/Library/Application Support/Alectrona/com.alectrona.AutomatedEnrollment.plist"
policyArray=()
unset caffeinatePID

# If we have these empty variables, we should exit
[[ -z "$company" ]] && writelog "Company (parameter 4) is not specified; exiting." && exit 1
[[ -z "$policyDetailString" ]] && writelog "PolicyDetailString (parameter 6) is not specified; exiting." && exit 2

# Build the policyArray splitting on ;
IFS=';' read -r -a policyArray <<< "$policyDetailString"

# If our policyArray does not contain at least one element then exit
[[ "${#policyArray[@]}" -lt "1" ]] && writelog "There is not at least one policy specified to run; exiting." && exit 3

function writelog () {
	if [[ -n "$1" ]]; then
		DATE=$(date +%Y-%m-%d\ %H:%M:%S)
		printf "%s\n" "$1"
		printf "%s\n" "$DATE  $1" >> "$log"
	else
		if test -t 0; then return; fi
        while IFS= read -r pipeData; do
			DATE=$(date +%Y-%m-%d\ %H:%M:%S)
			printf "%s\n" "$pipeData"
			printf "%s\n" "$DATE  $pipeData" >> "$log"
		done
	fi
}

function finish () {
	local exitCode=$?
	
    # Send exit to DEPNotify, clean up after ourselves, and kill the caffeinate process
    echo "Command: Quit" >> "$DEPNotifyConfig"
    
    /bin/rm -Rf $DEPNotifyApp
    [[ -f "/tmp/$companyLogoFilename" ]] && /bin/rm -f "$DEPNotifyConfig"
    [[ -f "/tmp/$companyLogoFilename" ]] && /bin/rm -f "/tmp/$companyLogoFilename"
    [[ -n "$caffeinatePID" ]] && /bin/ps -p "$caffeinatePID" > /dev/null && /bin/kill "$caffeinatePID"; wait "$caffeinatePID" 2>/dev/null
    writelog "$scriptName exiting with $exitCode"
    writelog "======== Finished $scriptName ========"
}

trap "finish" EXIT

function install_rosetta () {
    local arch
    arch=$(/usr/bin/arch)

    if [[ "$osMajorVersion" -ge 11 ]]; then
        if [[ "$arch" == "arm64" ]]; then
            echo "Apple Silicon Mac detected; Installing Rosetta."
            if /usr/bin/pgrep oahd >/dev/null 2>&1; then
                echo "Rosetta is already installed and running."
            else
                if /usr/sbin/softwareupdate --install-rosetta --agree-to-license ; then
                    echo "Rosetta has been successfully installed."
                else
                    echo "Error: Rosetta installation failed."
                    return 1
                fi
            fi
        elif [[ "$arch" == "i386" ]]; then
            echo "Intel Architecture detected; skipping Rosetta installation."
        else
            echo "Unknown Architecture detected; skipping Rosetta installation."
        fi
    else
        echo "No need to install Rosetta on macOS $osVersion."
    fi

    return 0
}

function install_package () {
    # Install the package
    local package="$1"
    if /usr/sbin/installer -pkg "$package" -target / >/dev/null; then
        /bin/rm "$package"
        return 0
    else
        /bin/rm "$package"
        return 1
    fi
}

function get_url () {
    # perform an HTTP get and save the file to the disk
	local URL="$1"
    local destination="$2"
	if /usr/bin/curl -fsSL --speed-time 60 --speed-limit 10000 "$URL" -o "$destination" 2>/dev/null ; then
        return 0
    else
        return 1
    fi
}

function wait_for_gui () {
    # Wait for the Dock to determine the current user
    dockStatus=$(/usr/bin/pgrep -x Dock)
    writelog "Waiting for Desktop..."

    while [[ "$dockStatus" == "" ]]; do
        writelog "Desktop is not loaded; waiting..."
        sleep 5
        dockStatus=$(/usr/bin/pgrep -x Dock)
    done

    loggedInUser=$( echo "show State:/Users/ConsoleUser" | /usr/sbin/scutil | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }' )
    loggedInUID=$(/usr/bin/id -u "$loggedInUser")
    writelog "$loggedInUser is logged in and at the desktop; continuing."
}

function check_jss_connection () {
    local jssURL jamfHelper title message icon jamfHelperPID tryConnectionCount exitCode

    jssURL=$(/usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url 2> /dev/null | /usr/bin/sed -e 's/\/$//')
    title="Connect to Internet"
    jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
    icon="/System/Library/PreferencePanes/Network.prefPane/Contents/Resources/Network.icns"
    tryConnectionCount="0"
    message="Please connect your computer to the internet.

This message will close automatically when you are done."

    if ! /usr/bin/curl -m 10 -ks "${jssURL}/healthCheck.html" > /dev/null; then
        writelog "Waiting for connection to the Jamf Pro server..."

        /bin/launchctl asuser "$loggedInUID" "$jamfHelper" -windowType "hud" -lockHUD -windowPosition ul -title "$title" -alignDescription natural -description "$message" -icon "$icon" &>/dev/null &
        jamfHelperPID=$!

        while true; do
            if /usr/bin/curl -m 10 -ks "${jssURL}/healthCheck.html" > /dev/null; then
                exitCode="0"
                break
            else
                ((tryConnectionCount++))
                sleep 1
                if [[ "$tryConnectionCount" -ge "600" ]]; then
                    writelog "Error; waited without successful connection for 10 minutes."
                    exitCode="1"
                    break
                fi
            fi
        done

        [[ "$jamfHelperPID" ]] && /bin/kill "$jamfHelperPID"; wait "$jamfHelperPID" 2>/dev/null
    else
        exitCode="0"
    fi

    return "$exitCode"
}

function check_updates () {
    updates=$(/usr/sbin/softwareupdate --list)
    local updateText="update"

	# Find updates that do require restarting or shut down
	# Account for the differences in pre/post Catalina softwareupdate -l output
	if [[ "$osMajorVersion" -eq "10" ]] && [[ "$osMinorVersion" -le 14 ]]; then
		updatesNoRestart=$(echo "$updates" | /usr/bin/grep -Ei "restart|shut down" -B1 | /usr/bin/diff --normal - <(echo "$updates") | /usr/bin/sed -n -e 's/^.*[\*|-] //p')
		updatesRestart=$(echo "$updates" | /usr/bin/grep -Ei "restart|shut down" -B1 | /usr/bin/grep -vEi 'restart|shut down' | /usr/bin/sed -n -e 's/^.*\* //p')
	elif [[ "$osMajorVersion" -eq "10" ]] && [[ "$osMinorVersion" -ge 15 ]]; then
		updatesNoRestart=$(echo "$updates" | /usr/bin/grep -Ei -B1 "restart|shut down" | /usr/bin/diff - <(echo "$updates") | /usr/bin/sed -n 's/.*Label://p')
		updatesRestart=$(echo "$updates" | /usr/bin/grep -Ei "restart|shut down" | /usr/bin/sed -e 's/.*Title: \(.*\), Ver.*/\1/')
    elif [[ "$osMajorVersion" -eq "11" ]]; then
		updatesNoRestart=$(echo "$updates" | /usr/bin/grep -Ei -B1 "restart|shut down" | /usr/bin/diff - <(echo "$updates") | /usr/bin/sed -n 's/.*Label://p')
		updatesRestart=$(echo "$updates" | /usr/bin/grep -Ei "restart|shut down" | /usr/bin/sed -e 's/.*Title: \(.*\), Ver.*/\1/')
    fi

    # How many updates do we have anyway?
    updatesNoRestartCount=$(echo -n "$updatesNoRestart" | grep -c '^')
    updatesRestartCount=$(echo -n "$updatesRestart" | grep -c '^')
    totalUpdateCount=$((updatesNoRestartCount + updatesRestartCount))

    [[ "$totalUpdateCount" -gt "1" ]] && updateText="updates"
    [[ "$totalUpdateCount" -gt "0" ]] && echo "Status: There are $totalUpdateCount $updateText to install, opening System Preferences..." >> "$DEPNotifyConfig"

    if [[ "$totalUpdateCount" -gt "0" ]]; then
        if [[ -n "$loggedInUser" ]]; then
            writelog "There are $totalUpdateCount $updateText to install, opening System Preferences for $loggedInUser."
            /bin/launchctl asuser "$loggedInUID" /usr/bin/open /System/Library/PreferencePanes/SoftwareUpdate.prefPane
        fi
    fi
}

writelog " "
writelog "======== Starting $scriptName ========"
[[ "$dryRun" == "true" ]] && writelog "Dry Run is configured, simulating workflow."

# Caffeinate the Mac so it does not sleep
/usr/bin/caffeinate -d -i -m -u &
caffeinatePID=$!

# Initially create a breadcrumb to mark an incomplete status, and this will update later in the process if successful
if [[ "$dryRun" != "true" ]]; then
    /bin/mkdir -p "/Library/Application Support/Alectrona"
    /usr/libexec/PlistBuddy -c "Delete :Complete" "$completionBreadcrumb" &> /dev/null
    /usr/libexec/PlistBuddy -c "Add :Complete bool false" "$completionBreadcrumb" &> /dev/null
fi

# Wait for a GUI
wait_for_gui

# Verify we have a good network connection before continuing
if ! check_jss_connection; then
    writelog "Failed to connect to the Jamf Pro server; exiting."
    exit 4
else
    writelog "Successfully connected to the Jamf Pro server; continuing."
fi

# Make sure we have a clean config file to start with
[[ -f "$DEPNotifyConfig" ]] && /bin/rm "$DEPNotifyConfig"

# Install Rosetta if necessary
if ! install_rosetta; then
    exit 5
fi

# Get the company's branding image
if get_url "$companyLogoURL" "/tmp/$companyLogoFilename" ; then
    writelog "Successfully downloaded $company logo."
    echo "Command: Image: /tmp/$companyLogoFilename" >> "$DEPNotifyConfig"
else
    writelog "Could not download $company logo; using default logo."
fi

# Download and install DEPNotify
if get_url "$DEPNotifyDownloadURL" "/tmp/$DEPNotifyPkg" ; then
    writelog "Successfully downloaded DEPNotify."
    if install_package "/tmp/$DEPNotifyPkg"; then
        if [[ -e "$DEPNotifyApp" ]]; then
            writelog "Successfully installed DEPNotify."
        else
            writelog "Failed to install DEPNotify; exiting."
            exit 6
        fi
    else
        writelog "An error occured durung the DEPNotify installation; exiting."
        exit 7
    fi
else
    writelog "Failed to download DEPNotify; exiting."
    exit 8
fi

# Open DepNotify App
/bin/launchctl asuser "$loggedInUID" /usr/bin/open -a "$DEPNotifyApp" --args -path "$DEPNotifyConfig"

# Configure DEPNotify
echo "Command: MainTitle: $company Automated Deployment" >> "$DEPNotifyConfig"
echo "Command: MainText: Thank you for choosing a Mac at $company! The following process will configure your Mac, install base software, and install any company-specific tools you might need." >> "$DEPNotifyConfig"
echo "Command: DeterminateOff" >> "$DEPNotifyConfig"
echo "Status: Pausing for a few seconds..." >> "$DEPNotifyConfig"

# Give the user a chance to read the initial screen, but don't require a button click to continue
sleep 10

# Reset the determinate
echo "Command: DeterminateOffReset:" >> "$DEPNotifyConfig"

# Determine the additional progress bar determinate count for actions taken outside of policies
[[ "$checkOSUpdates" != "false" ]] && additionalOptsCounter=$((additionalOptsCounter + 2))

# Checking policy array and adding the count from the additional options above.
determinateLength="$((${#policyArray[@]} + additionalOptsCounter))"
echo "Command: Determinate: $determinateLength" >> "$DEPNotifyConfig"

# echo "Command: MainTitle: Preparing your Mac for Deployment" >> "$DEPNotifyConfig"
echo "Command: MainTitle: Configuring your Mac" >> "$DEPNotifyConfig"
echo "Command: MainText: Please do not shutdown, reboot, or close your Mac. This window will automatically close when installation is complete." >> "$DEPNotifyConfig"

# Loop to run policies
for policy in "${policyArray[@]}"; do
    echo "Status: $(echo "$policy" | /usr/bin/cut -d ',' -f1)" >> "$DEPNotifyConfig"
    [[ "$dryRun" != "true" ]] && /usr/local/bin/jamf policy -event "$(echo "$policy" | /usr/bin/cut -d ',' -f2)" 2>&1 | writelog
    [[ "$dryRun" == "true" ]] && writelog "Simulating $(echo "$policy" | /usr/bin/cut -d ',' -f1)" && sleep 2
done

# Remove the user's admin privileges if configured to do so
if [[ "$demoteLoggedInUser" == "true" ]]; then
    if /usr/sbin/dseditgroup -o checkmember -m "$loggedInUser" admin &> /dev/null ; then
        writelog "Removing $loggedInUser's admin privileges..."
        [[ "$dryRun" != "true" ]] && /usr/sbin/dseditgroup -o edit -d "$loggedInUser" admin
    else
        writelog "$loggedInUser does not have admin privileges, skipping privileges removal."
    fi
fi

# Righe before the recon lets update our completion breadcrumb as the process is bound to succeed now
if [[ "$dryRun" != "true" ]]; then
    [[ -e "$completionBreadcrumb" ]] && /usr/libexec/PlistBuddy -c Clear "$completionBreadcrumb" &> /dev/null
    /usr/libexec/PlistBuddy -c "Add :Complete bool true" "$completionBreadcrumb"
fi

# Update inventory in Jamf Pro
echo "Status: Updating inventory in Jamf Pro Server..." >> "$DEPNotifyConfig"
echo "Command: MainTitle: Almost done!" >> "$DEPNotifyConfig"
[[ "$dryRun" != "true" ]] && /usr/local/bin/jamf recon 2>&1 | writelog
[[ "$dryRun" == "true" ]] && sleep 2

# Determine if we are supposed to check for updates
if [[ "$checkOSUpdates" != "false" ]]; then
    echo "Command: MainText: We are checking for macOS updates now. If any updates are available, System Preferences will open so that you can install them." >> "$DEPNotifyConfig"
    echo "Status: Checking for macOS updates..." >> "$DEPNotifyConfig"
    check_updates
fi

exit 0