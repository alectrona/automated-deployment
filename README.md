# Alectrona Automated Deployment
An easy to configure automated deployment workflow for macOS leveraging Jamf Pro and DEPNotify.

![Alectrona Logo](images/alectrona-logo-bird-and-text_600x139.png)

## Features
* Automatically downloads and installs [DEPNotify](https://gitlab.com/Mactroll/DEPNotify) so you don't have to.
* Allows for custom branding for your organization including downloading a custom logo of your choosing from the web to display in DEPNotify.
* Can be configured to check for and prompt to install macOS Software Updates (using System Preferences).
* Optionally can be configured to demote the currently logged-in user to a standard account.
* Installs [Rosetta 2](https://support.apple.com/en-us/HT211861) by default on Apple Silicon Macs prior to running Jamf Pro policies.
* Being completely configured using Jamf Pro script parameters, the same script can be used in multiple policies without changing the script itself.
* Allows for a Dry Run option so you can test the workflow without making any changes to the Mac.

## Deploy with Jamf Pro
1. Add the [automated-deployment.sh](automated-deployment.sh) script to your Jamf Pro server and set up the Parameter Labels by referencing [Jamf Pro Parameters](#jamf-pro-parameters).
2. Create a Jamf Pro policy using the following options:
    1. Options > General > Trigger: `Enrollment Complete`.
    2. Options > General > Execution Frequency: `Ongoing`.
    3. Options > Scripts > Add the script you created in Step 1 and configure the Parameters by referencing [Jamf Pro Parameters](#jamf-pro-parameters).
    4. Scope > Define a target for the policy. *Typically in production this would be "All Computers"*.
3. Enroll a computer and test.

## Jamf Pro Parameters
When adding the script to Jamf Pro, you will configure the labels for Parameters 4 through 9 using the information below. Additionally, the descriptions below will help you populate the Parameters within your Jamf Pro policy.

| Parameter | Parameter Label | Description |
| ----------- | --------------- | ----------- |
| Parameter 4 | Company | The company name to display in DEPNotify. |
| Parameter 5 | Company Logo URL | The URL of an image to download and display as the title image in DEPNotify. |
| Parameter 6 | Policy Detail String | A specifically formatted string that combines DEPNotify Status and Jamf Pro policy Custom Events. See [Policy Detail String](#policy-detail-string) for more details. |
| Parameter 7 | Check macOS Updates (`true`\|`false`) | Set to `true` to check for macOS updates and display System Preferences. Leaving this parameter empty will default to `true`.        |
| Parameter 8 | Demote Logged-In User (`true`\|`false`) | Set to `true` to demote the current logged-in user to a standard account. Leaving this parameter empty will default to `false`. |
| Parameter 9 | Dry Run (`true`\|`false`) | Set to `true` to test the workflow without making any changes to the Mac. Leaving this parameter empty will default to `false`. |

## Policy Detail String
The Policy Detail String is a specifically formatted string that combines DEPNotify Status and Jamf Pro policy Custom Events. This allows you to configure just one parameter, but define many policies to execute. Consequently, this eliminates the need to have separate copies of the same script for use with different workflows within your environment.

Lets break down the following Policy Detail String:

```Installing Google Chrome...,google-chrome;Installing Security software...,jamf-protect```

Starting at the beginning, `Installing Google Chrome...` is the Status displayed in DEPNotify. Additionally, `google-chrome` is the Jamf Pro Custom Event that will be executed **while** `Installing Google Chrome...` is being displayed. The DEPNotify Status is separated from the Custom Event by a comma (`,`). Next, a semi-colon (`;`) separates each DEPNotify Status/Custom Event combination.

To easily create your own Policy Detail String we've included [generate-policy-detail-string.sh](generate-policy-detail-string.sh). Simply:
1. Modify the `policyDetailArray` variable while preserving the original format.
2. Execute the script locally.

Your Policy Detail String will print to the console and will be copied to your clipboard for use in Parameter 6 in your Jamf Pro policy.