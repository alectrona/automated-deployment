#!/bin/bash

# Policy Detail String Generator

# Generates the Policy Detail String used for the Alectrona Automated Deployment
# script in a Jamf Pro policy (as Parameter 6).

# Created by Alectrona for use with https://github.com/alectrona/automated-deployment

policyDetailArray=(
    "Renaming this Mac...,rename-mac"
    "Enabling FileVault...,enable-filevault"
    "Installing Google Chrome...,google-chrome"
    "Installing Security software...,jamf-protect"
)

# Code beyond this point is not inteded to be modified
policyDetailString=$(printf "%s;" "${policyDetailArray[@]}" | /usr/bin/sed 's/;*$//g')

echo "The following Policy Detail String has been copied to your clipboard:"

echo "$policyDetailString"
echo "$policyDetailString" | /usr/bin/pbcopy

exit 0