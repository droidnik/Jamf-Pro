#!/bin/zsh

# ==== JAMF CONNECT - COMPREHENSIVE ACCOUNT NAME ANALYSIS ====
# Zweck: Vollständige Analyse von Account-Mismatches
# 1. NetworkUser vs preferred_username (noch nicht synchronisiert)
# 2. IdToken name vs lokaler RealName (Namensänderung nach Sync)

# Get current signed in user
currentUser=$(stat -f%Su /dev/console)

# Skip system users
if [[ "$currentUser" == "loginwindow" ]] || [[ "$currentUser" == "_mbsetupuser" ]] || [[ "$currentUser" == "root" ]]; then
    echo "<result>No regular user logged in</result>"
    exit 0
fi

# Check if user exists
if ! id "$currentUser" &>/dev/null; then
    echo "<result>User $currentUser does not exist</result>"
    exit 0
fi

# ==== GET PREFERRED USERNAME FROM JAMF CONNECT STATE ====
jamfConnectStateFile="/Users/${currentUser}/Library/Preferences/com.jamf.connect.state.plist"

# Check if Jamf Connect State file exists
if [[ ! -f "$jamfConnectStateFile" ]]; then
    echo "<result>Local account - no Jamf Connect state found</result>"
    exit 0
fi

# Get preferred_username from IdToken in Jamf Connect State
preferredUsername=$(sudo -u "$currentUser" /usr/libexec/PlistBuddy -c "Print :IdToken:preferred_username" "$jamfConnectStateFile" 2>/dev/null)

if [[ -z "$preferredUsername" ]]; then
    echo "<result>ERROR: No preferred_username found in Jamf Connect state</result>"
    exit 0
fi

# Get name from IdToken (for display name comparison)
idTokenName=$(sudo -u "$currentUser" /usr/libexec/PlistBuddy -c "Print :IdToken:name" "$jamfConnectStateFile" 2>/dev/null)

# Get NetworkUser from Directory Service
networkUser=$(dscl . -read /Users/${currentUser} | grep "^NetworkUser:" | awk -F': ' '{print $2}' | xargs)

if [[ -z "$networkUser" || "$networkUser" == "NetworkUser:" ]]; then
    echo "<result>ERROR: No NetworkUser found</result>"
    exit 0
fi

# Get RealName from local user account (robust method for single/multiline)
realName=$(dscl . -read /Users/${currentUser} RealName 2>/dev/null | sed '1d' | tr -d '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

# Fallback: try alternative method if RealName is empty
if [[ -z "$realName" ]]; then
    realName=$(dscl . -read /Users/${currentUser} | grep "^RealName:" | sed 's/^RealName:[[:space:]]*//' | tr -d '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
fi

# ==== COMPREHENSIVE ANALYSIS ====
networkUserMismatch=false
nameMismatch=false

# Check 1: NetworkUser vs preferred_username (not yet synchronized)
# Convert both to lowercase for case-insensitive comparison (email addresses)
networkUserLower="${networkUser:l}"
preferredUsernameLower="${preferredUsername:l}"

if [[ "$networkUserLower" != "$preferredUsernameLower" ]]; then
    networkUserMismatch=true
fi

# Check 2: IdToken name vs RealName (name change after sync)
if [[ -n "$idTokenName" && -n "$realName" && "$idTokenName" != "$realName" ]]; then
    nameMismatch=true
fi

# Build comprehensive result
if [[ "$networkUserMismatch" == "true" && "$nameMismatch" == "true" ]]; then
    echo "<result>DOUBLE MISMATCH: NetworkUser ($networkUser ≠ $preferredUsername) + Name ($realName ≠ $idTokenName)</result>"
elif [[ "$networkUserMismatch" == "true" ]]; then
    echo "<result>NETWORK MISMATCH: NetworkUser ($networkUser) ≠ preferred_username ($preferredUsername)</result>"
elif [[ "$nameMismatch" == "true" ]]; then
    echo "<result>NAME CHANGE DETECTED: RealName ($realName) ≠ IdToken name ($idTokenName) | NetworkUser OK</result>"
else
    echo "<result>SYNCHRONIZED: NetworkUser = $networkUser | RealName = $realName</result>"
fi
