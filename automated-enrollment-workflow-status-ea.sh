#!/bin/bash

# Automated Enrollment Workflow Status

# This attribute reads a breadcrumb to determine if the computer has completed the Automated Enrollment Workflow or not.

# Created by Alectrona for use with https://github.com/alectrona/automated-deployment

completionBreadcrumb="/Library/Application Support/Alectrona/com.alectrona.AutomatedEnrollment.plist"
result=$(/usr/bin/defaults read "$completionBreadcrumb" Complete 2> /dev/null)

# If the breadcrumb reads false then return incomplete, and true means complete
if [[ "$result" == "0" ]]; then
    echo "<result>Incomplete</result>"
elif [[ "$result" == "1" ]]; then
    echo "<result>Complete</result>"
fi

exit 0