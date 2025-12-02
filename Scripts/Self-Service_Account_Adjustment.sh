#!/bin/zsh --no-rcs

# ==== SELF SERVICE: ACCOUNT ADJUSTMENT ====
# Adjusts user account to match current email from Azure AD/Jamf Connect
# Options: Display name only OR complete adjustment (username + home folder)
#
# USAGE:
#   Normal:     sudo ./Self-Service_Account_Adjustment.sh
#   Test Mode:  sudo ./Self-Service_Account_Adjustment.sh --test
#
# TEST MODE: Shows all steps but doesn't perform actual changes

# ==== VARIABLES ====
currentUser=$(stat -f%Su /dev/console)
dialogApp="/usr/local/bin/dialog"
dialogTitle="Username and Folder Adjustment"
dialogIcon="SF=person.badge.key"

# Modern Design Parameters
bannerImage=<your Company Banner>
bannerHeight="65"
dialogWidth="800"
dialogHeight="600"
iconSize="80"

# ==== TEST MODE ====
TEST_MODE=false
if [[ -n "$1" && "$1" == "--test" ]]; then
    TEST_MODE=true
    dialogTitle="Username and Folder Adjustment (TEST MODE)"
    dialogIcon="SF=hammer.and.wrench.fill"
    iconSize="120"
    echo "TEST MODE activated - No real changes will be performed!"
fi

# ==== FUNCTIONS ====
# ==== DISPLAY NAME ADJUSTMENT (SIMPLE) ====
perform_display_name_only() {
    local targetDisplayName="$1"
    
    echo "PROCESSING: Performing simple display name adjustment..."
    
    # Single persistent dialog with updates
    local commandFile="/var/tmp/dialog_display.log"
    
    # Start the dialog
    dialog_command --message "## Display Name Adjustment

**Current Status:**
• Username: **$currentUser** (unchanged)  
• Display name: **$targetDisplayName**  
• Home folder: /Users/$currentUser (unchanged)  

**Preparing adjustment...**" --progress 10 --button1text "none" --moveable --ontop --height 500 --commandfile "$commandFile" &
    dialogPID=$!
    
    sleep 3
    
    # Update: Processing
    echo "progress: 30" >> "$commandFile"
    echo "progresstext: Processing display name change..." >> "$commandFile"
    echo "message: ## Display Name Adjustment<br><br>**Setting display name...**<br><br>• Username: **$currentUser** (unchanged)<br>• Display name: **$targetDisplayName**<br>• Status: WORKING - Processing..." >> "$commandFile"
    
    sleep 3
    
    if [[ "$TEST_MODE" == "true" ]]; then
        echo "TEST MODE: Would set display name:"
        echo "TEST: dscl . -change \"/Users/${currentUser}\" RealName \"\" \"$targetDisplayName\""
        echo "TEST: /usr/local/bin/jamf recon -endUsername \"$currentEmail\""
        
        # Update: Simulating
        echo "progress: 60" >> "$commandFile"
        echo "progresstext: Simulating display name change..." >> "$commandFile"
        echo "message: ## Display Name Adjustment<br><br>**TEST MODE - Simulating...**<br><br>• Username: **$currentUser** (unchanged)<br>• Display name: **$targetDisplayName**<br>• Files: completely preserved<br><br>**No real changes performed!**" >> "$commandFile"
    else
        # Update: Real execution
        echo "progress: 60" >> "$commandFile"
        echo "progresstext: Setting display name..." >> "$commandFile"
        
        # Set RealName (display name) - change existing value
        dscl . -change "/Users/${currentUser}" RealName "" "$targetDisplayName" 2>/dev/null || \
        dscl . -create "/Users/${currentUser}" RealName "$targetDisplayName"
        echo "Display name set: $targetDisplayName"
        
        # Update dialog
        echo "progress: 80" >> "$commandFile"
        echo "progresstext: Updating Jamf inventory..." >> "$commandFile"
        
        # Update Jamf with email (not username!)
        if [[ -n "$currentEmail" ]]; then
            /usr/local/bin/jamf recon -endUsername "$currentEmail"
            echo "Jamf computer object updated"
        fi
    fi
    
    sleep 1
    
    # Final update: Complete progress first, then update content
    if [[ "$TEST_MODE" == "true" ]]; then
        echo "progress: 100" >> "$commandFile"
        echo "progresstext: Test completed successfully!" >> "$commandFile"
        sleep 1
        echo "message: # TEST MODE: Simulation completed!<br><br>**What would happen in real mode:**<br><br>• **Display name:** $targetDisplayName<br>• **Username:** $currentUser (unchanged)<br>• **Files:** completely preserved<br><br>---<br>## SUCCESS: Test successful!<br><br>**Benefits:** No logout required, completely safe<br><br>**Click OK to close**" >> "$commandFile"
        echo "button1text: OK" >> "$commandFile"
        sleep 1
        echo "progress: " >> "$commandFile"  # Remove progress bar
    else
        echo "progress: 100" >> "$commandFile"
        echo "progresstext: Adjustment completed successfully!" >> "$commandFile"
        sleep 1
        echo "message: # Display name successfully adjusted!<br><br>**Your changes:**<br><br>• **Display name:** $targetDisplayName<br>• **Username:** $currentUser (unchanged)<br>• **Files:** completely preserved<br><br>---<br>## SUCCESS: Adjustment complete!<br><br>**Continue with:** $currentUser<br>**No logout required**<br><br>**Click OK to close**" >> "$commandFile"
        echo "button1text: OK" >> "$commandFile"
        sleep 1
        echo "progress: " >> "$commandFile"  # Remove progress bar
    fi
    
    # Wait for user to click OK
    wait $dialogPID
    
    # Clean up
    rm -f "$commandFile" 2>/dev/null
    
    if [[ "$TEST_MODE" == "true" ]]; then
        echo ""
        echo "USERNAME ADJUSTMENT TEST COMPLETED!"
    else
        echo ""
        echo "DISPLAY NAME ADJUSTMENT COMPLETED!"
    fi
}
dialog_command() {
    "$dialogApp" --title "$dialogTitle" --icon "$dialogIcon" \
        --bannerimage "$bannerImage" \
        --bannerheight "$bannerHeight" \
        --width "$dialogWidth" \
        --iconsize "$iconSize" "$@"
}

# Enhanced dialog functions using command files for consistency
show_error() {
    dialog_command --message "$1" --button1text "OK" --messagefont "color=red" --height 500
}

show_info() {
    dialog_command --message "$1" --button1text "OK" --height 500
}

# Updated show_success to work with existing dialog or create new one
show_success() {
    local message="$1"
    local commandFile="$2"
    
    if [[ -n "$commandFile" && -f "$commandFile" ]]; then
        # Update existing dialog
        echo "message: $message" >> "$commandFile"
        echo "button1text: OK" >> "$commandFile"
        echo "progress: " >> "$commandFile"  # Remove progress bar
        echo "progresstext: Ready to close" >> "$commandFile"  # Clear progress text
    else
        # Create new dialog (fallback)
        dialog_command --message "$message" --button1text "OK" --height "$dialogHeight"
    fi
}

# ==== ROOT CHECK ====
if [[ "${UID}" != 0 ]]; then
  show_error "ERROR: This script must be run as root."
  exit 1
fi

# ==== SWIFTDIALOG CHECK ====
if [[ ! -x "$dialogApp" ]]; then
    echo "ERROR: SwiftDialog not found at $dialogApp"
    echo "Installing SwiftDialog..."
    exit 1
fi

# Check SwiftDialog version (for compatibility)
dialogVersion=$("$dialogApp" --version 2>/dev/null | head -1 | awk '{print $NF}')
echo "INFO: SwiftDialog Version: $dialogVersion"

echo "=== SELF SERVICE: USERNAME ADJUSTMENT ==="
echo "Current User: $currentUser"
echo "================================================="

# ==== USER CHECKS ====
if ! id "$currentUser" >/dev/null 2>&1; then
  show_error "ERROR: User $currentUser does not exist!"
  exit 1
fi

# ==== CHECK NETWORK CONNECTION ====
echo "Checking network connection..."

# Standard Jamf Connect attributes (newer versions)
networkUser=$(dscl . -read /Users/${currentUser} dsAttrTypeStandard:NetworkUser 2>/dev/null | awk '{print $2}')
oidcProvider=$(dscl . -read /Users/${currentUser} dsAttrTypeStandard:OIDCProvider 2>/dev/null | awk '{print $2}')
oktaUser=$(dscl . -read /Users/${currentUser} dsAttrTypeStandard:OktaUser 2>/dev/null | awk '{print $2}')
azureUser=$(dscl . -read /Users/${currentUser} dsAttrTypeStandard:AzureUser 2>/dev/null | awk '{print $2}')

# Legacy attributes (older Jamf Connect versions)
azureUPN=$(dscl . -read /Users/${currentUser} AzureUserPrincipalName 2>/dev/null | awk '{print $2}')
userEmail=$(dscl . -read /Users/${currentUser} EMailAddress 2>/dev/null | awk '{print $2}')
authAuth=$(dscl . -read /Users/${currentUser} AuthenticationAuthority 2>/dev/null | awk '{print $2}')

# Debug: Show all found attributes
echo ""
echo "DEBUG: Found attributes:"
echo "  networkUser: '$networkUser'"
echo "  oidcProvider: '$oidcProvider'" 
echo "  oktaUser: '$oktaUser'"
echo "  azureUser: '$azureUser'"
echo "  azureUPN: '$azureUPN'"
echo "  userEmail: '$userEmail'"
echo "  authAuth: '$authAuth'"

if [[ -z "$networkUser$oidcProvider$oktaUser$azureUser$azureUPN$userEmail$authAuth" ]]; then
    show_error "ERROR: Account has no network connection!

INFO: **Next steps:**  
1. Run 'Email/Name Change' in Self Service
2. Log in with new email
3. Then run 'Username Adjustment' again"
    exit 1
fi

# Compile current email for dialog (Priority: NetworkUser > OktaUser > AzureUser > Legacy)
currentEmail=""
if [[ -n "$networkUser" && "$networkUser" != "dsAttrTypeStandard:NetworkUser:" ]]; then
    currentEmail="$networkUser"
    echo "Email source: NetworkUser"
elif [[ -n "$oktaUser" && "$oktaUser" != "dsAttrTypeStandard:OktaUser:" ]]; then
    currentEmail="$oktaUser"
    echo "Email source: OktaUser"
elif [[ -n "$azureUser" && "$azureUser" != "dsAttrTypeStandard:AzureUser:" ]]; then
    currentEmail="$azureUser"
    echo "Email source: AzureUser"
elif [[ -n "$azureUPN" && "$azureUPN" != "AzureUserPrincipalName:" ]]; then
    currentEmail="$azureUPN"
    echo "Email source: AzureUPN (Legacy)"
elif [[ -n "$userEmail" && "$userEmail" != "EMailAddress:" ]]; then
    currentEmail="$userEmail"
    echo "Email source: EMailAddress (Legacy)"
else
    currentEmail="(Network connection present, but email not recognizable)"
    echo "Email source: Not recognized"
fi

echo "DEBUG: Used email: '$currentEmail'"

# ==== GET REALNAME AND IDTOKEN NAME ====
echo ""
echo "Retrieving display names..."

# Get RealName from local user account (robust method for single/multiline)
realName=$(dscl . -read /Users/${currentUser} RealName 2>/dev/null | sed '1d' | tr -d '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

# Fallback: try alternative method if RealName is empty
if [[ -z "$realName" ]]; then
    realName=$(dscl . -read /Users/${currentUser} | grep "^RealName:" | sed 's/^RealName:[[:space:]]*//' | tr -d '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
fi

echo "DEBUG: Current RealName: '$realName'"

# Get IdToken name from Jamf Connect State Plist
jamfConnectStateFile="/Users/${currentUser}/Library/Preferences/com.jamf.connect.state.plist"
idTokenName=""

if [[ -f "$jamfConnectStateFile" ]]; then
    idTokenName=$(sudo -u "$currentUser" /usr/libexec/PlistBuddy -c "Print :IdToken:name" "$jamfConnectStateFile" 2>/dev/null)
    if [[ "$idTokenName" == "Does Not Exist" ]]; then
        idTokenName=""
    fi
fi

echo "DEBUG: IdToken name: '$idTokenName'"

# Check for name mismatch (for display purposes)
nameMismatch=false
nameMismatchIndicator=""
if [[ -n "$idTokenName" && -n "$realName" && "$idTokenName" != "$realName" ]]; then
    nameMismatch=true
    nameMismatchIndicator=" (MISMATCH DETECTED)"
    echo "INFO: Name mismatch detected - will be shown in dialog"
fi

# ==== DETERMINE NEW USERNAME ====
# Normalize username (remove spaces, lowercase)
normalize_username() {
    local input="$1"
    # Remove spaces, convert to lowercase, replace umlauts
    echo "$input" | tr '[:upper:]' '[:lower:]' | sed 's/ //g' | sed 's/ä/ae/g; s/ö/oe/g; s/ü/ue/g; s/ß/ss/g'
}

# Format RealName to "Lastname, Firstname"
format_realname() {
    local input="$1"
    
    # Debug output
    echo "DEBUG: format_realname input: '$input'" >&2
    
    # Simple approach: split on dot and handle the parts
    if [[ "$input" == *"."* ]]; then
        local firstname=$(echo "$input" | cut -d'.' -f1)
        local lastname=$(echo "$input" | cut -d'.' -f2)
        
        echo "DEBUG: Split on dot - firstname: '$firstname', lastname: '$lastname'" >&2
        
        # Validate that we have both parts
        if [[ -n "$firstname" && -n "$lastname" ]]; then
            # Capitalize first letters, lowercase the rest
            firstname="$(echo "${firstname:0:1}" | tr '[:lower:]' '[:upper:]')$(echo "${firstname:1}" | tr '[:upper:]' '[:lower:]')"
            lastname="$(echo "${lastname:0:1}" | tr '[:lower:]' '[:upper:]')$(echo "${lastname:1}" | tr '[:upper:]' '[:lower:]')"
            
            echo "DEBUG: Formatted - firstname: '$firstname', lastname: '$lastname'" >&2
            echo "$lastname, $firstname"
            return
        else
            echo "DEBUG: One part is empty after split" >&2
        fi
    fi
    
    # Check if space is present as separator
    if [[ "$input" == *" "* ]]; then
        local firstname=$(echo "$input" | cut -d' ' -f1)
        local lastname=$(echo "$input" | cut -d' ' -f2)
        
        echo "DEBUG: Split on space - firstname: '$firstname', lastname: '$lastname'" >&2
        
        # Validate that we have both parts
        if [[ -n "$firstname" && -n "$lastname" ]]; then
            # Capitalize first letters
            firstname="$(echo "${firstname:0:1}" | tr '[:lower:]' '[:upper:]')$(echo "${firstname:1}" | tr '[:upper:]' '[:lower:]')"
            lastname="$(echo "${lastname:0:1}" | tr '[:lower:]' '[:upper:]')$(echo "${lastname:1}" | tr '[:upper:]' '[:lower:]')"
            
            echo "DEBUG: Formatted - firstname: '$firstname', lastname: '$lastname'" >&2
            echo "$lastname, $firstname"
            return
        fi
    fi
    
    # Fallback: return input with proper capitalization
    echo "DEBUG: No separator found, using input as-is: '$input'" >&2
    local formatted="$(echo "${input:0:1}" | tr '[:lower:]' '[:upper:]')$(echo "${input:1}" | tr '[:upper:]' '[:lower:]')"
    echo "DEBUG: Capitalized fallback: '$formatted'" >&2
    echo "$formatted"
}

# Get display name from Jamf Connect State Plist (most authoritative source)
get_display_name_from_jamf_connect() {
    local jamfConnectStateFile="/Users/${currentUser}/Library/Preferences/com.jamf.connect.state.plist"
    local displayName=""
    
    if [[ -f "$jamfConnectStateFile" ]]; then
        # Priority 1: IdToken.name (most authoritative from Azure AD - already perfectly formatted!)
        displayName=$(sudo -u "$currentUser" /usr/libexec/PlistBuddy -c "Print :IdToken:name" "$jamfConnectStateFile" 2>/dev/null)
        if [[ -n "$displayName" && "$displayName" != "Does Not Exist" ]]; then
            echo "DEBUG: Found IdToken.name: '$displayName'" >&2
            echo "$displayName"
            return
        fi
        
        # Priority 2: UserCN (Common Name) as fallback
        displayName=$(sudo -u "$currentUser" defaults read "$jamfConnectStateFile" UserCN 2>/dev/null)
        if [[ -n "$displayName" ]]; then
            echo "DEBUG: Found UserCN: '$displayName'" >&2
            echo "$displayName"
            return
        fi
        
        # Priority 3: UserFullName as fallback
        displayName=$(sudo -u "$currentUser" defaults read "$jamfConnectStateFile" UserFullName 2>/dev/null)
        if [[ -n "$displayName" ]]; then
            echo "DEBUG: Found UserFullName: '$displayName'" >&2
            echo "$displayName"
            return
        fi
    fi
    
    echo "DEBUG: No display name found in Jamf Connect State" >&2
    echo ""
}

determine_new_username() {
    local newUsername=""
    local rawUsername=""
    
    echo "Determining optimal username from Jamf Connect State..." >&2
    
    # ==== ONLY SOURCE: Jamf Connect State Plist ====
    local jamfConnectStateFile="/Users/${currentUser}/Library/Preferences/com.jamf.connect.state.plist"
    
    if [[ ! -f "$jamfConnectStateFile" ]]; then
        echo "ERROR: Jamf Connect State Plist not found at: $jamfConnectStateFile" >&2
        echo "NONE"
        return
    fi
    
    echo "Reading from Jamf Connect State Plist..." >&2
    
    # Try preferred_username (usually the email)
    local preferredUsername=$(sudo -u "$currentUser" /usr/libexec/PlistBuddy -c "Print :IdToken:preferred_username" "$jamfConnectStateFile" 2>/dev/null)
    
    if [[ -n "$preferredUsername" && "$preferredUsername" != "Does Not Exist" ]]; then
        echo "Found preferred_username: '$preferredUsername'" >&2
        rawUsername=$(echo "$preferredUsername" | cut -d'@' -f1)
        newUsername=$(normalize_username "$rawUsername")
        echo "Raw: '$rawUsername' → Normalized: '$newUsername'" >&2
        
        if [[ "$newUsername" == "$currentUser" ]]; then
            echo "Username is already optimal: $newUsername" >&2
            echo "SAME"
            return
        fi
        
        echo "$newUsername"
        return
    fi
    
    # Try upn (UserPrincipalName) as alternative
    local upn=$(sudo -u "$currentUser" /usr/libexec/PlistBuddy -c "Print :IdToken:upn" "$jamfConnectStateFile" 2>/dev/null)
    
    if [[ -n "$upn" && "$upn" != "Does Not Exist" ]]; then
        echo "Found upn: '$upn'" >&2
        rawUsername=$(echo "$upn" | cut -d'@' -f1)
        newUsername=$(normalize_username "$rawUsername")
        echo "Raw: '$rawUsername' → Normalized: '$newUsername'" >&2
        
        if [[ "$newUsername" == "$currentUser" ]]; then
            echo "Username is already optimal: $newUsername" >&2
            echo "SAME"
            return
        fi
        
        echo "$newUsername"
        return
    fi
    
    # Try email as last resort
    local email=$(sudo -u "$currentUser" /usr/libexec/PlistBuddy -c "Print :IdToken:email" "$jamfConnectStateFile" 2>/dev/null)
    
    if [[ -n "$email" && "$email" != "Does Not Exist" ]]; then
        echo "Found email: '$email'" >&2
        rawUsername=$(echo "$email" | cut -d'@' -f1)
        newUsername=$(normalize_username "$rawUsername")
        echo "Raw: '$rawUsername' → Normalized: '$newUsername'" >&2
        
        if [[ "$newUsername" == "$currentUser" ]]; then
            echo "Username is already optimal: $newUsername" >&2
            echo "SAME"
            return
        fi
        
        echo "$newUsername"
        return
    fi
    
    # No valid data found
    echo "ERROR: No valid email found in Jamf Connect State Plist" >&2
    echo "Checked: preferred_username, upn, email" >&2
    echo "NONE"
}

newUser=$(determine_new_username)

# Debug: Show what was actually determined before normalization
echo ""
echo "DEBUG: Raw determined newUser: '$newUser'"

# Prüfe Ergebnis BEVOR Normalisierung
if [[ "$newUser" == "SAME" && "$TEST_MODE" != "true" && "$nameMismatch" != "true" ]]; then
    show_success "**No adjustment required!**

**Current Status:**  
• Username: **$currentUser**  
• Display name (local): **$realName**  
• Display name (Azure AD): **$idTokenName**  
• Email: **$currentEmail**  

Your username is already optimally adjusted to your email!

**This means:**  
• No action required  
• Account is correctly configured  
• Username matches email prefix  "
    exit 0
fi

if [[ "$newUser" == "NONE" ]]; then
    show_error "ERROR: **Automatic adjustment not possible**

**Reason:** The optimal username could not be determined automatically.

INFO: **Next steps:**
• Contact IT support
• Manual adjustment required
• Provide your new email: **$currentEmail**"
    exit 0
fi

# Username und Home-Ordner immer in Kleinbuchstaben (NACH den SAME/NONE checks!)
if [[ "$newUser" == "SAME" ]]; then
    # Username already correct - use current user for validation and display
    newUser="$currentUser"
    if [[ "$TEST_MODE" == "true" ]]; then
        echo "TEST MODE: Username already correct - using '$newUser'"
    else
        echo "Username already correct - using '$newUser' for display"
    fi
else
    newUser=$(echo "$newUser" | tr '[:upper:]' '[:lower:]')
fi


# Debug: Show final normalized username
echo "DEBUG: Final normalized newUser: '$newUser'"
echo "DEBUG: Length: ${#newUser}"

# ==== SECURITY CHECKS ====
if [[ -z "$newUser" ]]; then
    echo "ERROR: New username not determined!"
    exit 1
fi

if id "$newUser" >/dev/null 2>&1; then
    # Check if the existing user is actually the current user (including secondary RecordNames from Jamf Connect)
    currentUserUID=$(id -u "$currentUser" 2>/dev/null)
    newUserUID=$(id -u "$newUser" 2>/dev/null)
    
    # Also check if newUser is already a RecordName of the current user (Jamf Connect scenario)
    currentUserRecordNames=$(dscl . -read /Users/"$currentUser" RecordName 2>/dev/null | cut -d' ' -f2- | tr ' ' '\n')
    
    if [[ "$currentUserUID" == "$newUserUID" ]] || echo "$currentUserRecordNames" | grep -q "^$newUser$"; then
        # Same user or already a RecordName - username already correct or partially set
        echo "DEBUG: User $newUser already exists as RecordName for $currentUser"
        echo "DEBUG: Current RecordNames: $currentUserRecordNames"
        
        # Check if primary RecordName needs to be changed
        primaryRecordName=$(echo "$currentUserRecordNames" | head -1)
        if [[ "$primaryRecordName" == "$newUser" && "$nameMismatch" != "true" ]]; then
            show_success "**Username already correct!**

**Current Status:**  
• Username: **$newUser** (already optimal)  
• Display name (local): **$realName**  
• Display name (Azure AD): **$idTokenName**  
• Email: **$currentEmail**  

Your username is already correctly set to match your email prefix!

INFO: **This means:**  
• No adjustment needed  
• Account is perfectly configured  
• Username matches email prefix perfectly"
            exit 0
        else
            echo "DEBUG: Primary RecordName needs to be switched from $primaryRecordName to $newUser"
            # Continue with the renaming process - it will switch the primary RecordName
        fi
    else
        # Different user with same name - real conflict
        show_error "ERROR: **Username conflict detected!**

**Problem:** Username '$newUser' already exists in the system and belongs to a different user.

INFO: **Solution:**
• Contact IT support
• Manual adjustment required
• Provide the following data:
  - Current username: **$currentUser**
  - Desired username: **$newUser**
  - New email: **$currentEmail**"
        exit 1
    fi
fi

if [[ ! "$newUser" =~ ^[a-z][a-z0-9._-]*$ ]]; then
    show_error "ERROR: **Username format invalid!**

**Problem:** Username '$newUser' does not match the expected format.

INFO: **Solution:**
• Contact IT support
• Special adjustment required
• Email: **$currentEmail**"
    exit 1
fi

# ==== CONFIRMATION DIALOG ====
# Show both original and normalized username
originalEmailPrefix=""
if [[ -n "$networkUser" && "$networkUser" != "dsAttrTypeStandard:NetworkUser:" ]]; then
    originalEmailPrefix=$(echo "$networkUser" | cut -d'@' -f1)
    echo "DEBUG: originalEmailPrefix from networkUser: '$originalEmailPrefix'" >&2
elif [[ -n "$oktaUser" && "$oktaUser" != "dsAttrTypeStandard:OktaUser:" ]]; then
    originalEmailPrefix=$(echo "$oktaUser" | cut -d'@' -f1)
    echo "DEBUG: originalEmailPrefix from oktaUser: '$originalEmailPrefix'" >&2
elif [[ -n "$azureUser" && "$azureUser" != "dsAttrTypeStandard:AzureUser:" ]]; then
    originalEmailPrefix=$(echo "$azureUser" | cut -d'@' -f1)
    echo "DEBUG: originalEmailPrefix from azureUser: '$originalEmailPrefix'" >&2
elif [[ -n "$azureUPN" && "$azureUPN" != "AzureUserPrincipalName:" ]]; then
    originalEmailPrefix=$(echo "$azureUPN" | cut -d'@' -f1)
    echo "DEBUG: originalEmailPrefix from azureUPN: '$originalEmailPrefix'" >&2
elif [[ -n "$userEmail" && "$userEmail" != "EMailAddress:" ]]; then
    originalEmailPrefix=$(echo "$userEmail" | cut -d'@' -f1)
    echo "DEBUG: originalEmailPrefix from userEmail: '$originalEmailPrefix'" >&2
fi

echo "DEBUG: Final originalEmailPrefix: '$originalEmailPrefix'" >&2

# Build status section for dialog
statusSection="**Current Status:**<br>• Username: **$currentUser**<br>• Email: **$currentEmail**"

# Add RealName info if available
if [[ -n "$realName" ]]; then
    statusSection="${statusSection}<br>• Display name (local): **$realName**"
fi

# Add IdToken name info if available
if [[ -n "$idTokenName" ]]; then
    statusSection="${statusSection}<br>• Display name (Azure AD): **$idTokenName**"
fi

# Add mismatch warning if needed
if [[ "$nameMismatch" == "true" ]]; then
    statusSection="${statusSection}<br>• **WARNING: Display names do not match!**"
fi

# Determine what display name will be set
targetDisplayName=""
if [[ -n "$idTokenName" ]]; then
    targetDisplayName="$idTokenName"
elif [[ -n "$originalEmailPrefix" ]]; then
    targetDisplayName="$originalEmailPrefix"
else
    targetDisplayName="$newUser"
fi

# Main selection
echo "DEBUG: About to show main dialog..." >&2
mainChoice=$(dialog_command --message "### Choose your preferred option:<br><br>${statusSection}<br><br>---<br>**OPTION 1: Display name only** (Recommended)<br>• Quick and safe<br>• No risk, no logout<br>• Display name will be set to: **${targetDisplayName}**<br>• Username remains **$currentUser**<br>• Home folder remains /Users/$currentUser<br><br>**OPTION 2: Complete adjustment**<br>• WARNING: Requires logout and restart<br>• Display name will be set to: **${targetDisplayName}**<br>• Username will be changed to **$newUser**<br>• Home folder will be renamed to **/Users/$newUser**<br>• All files and settings moved automatically<br>• Permissions remain correct (UID unchanged)<br>• Scripts will find files at new path<br>• Clean restart ensures proper completion<br><br>---<br>INFO: **Recommendation:** Start with Option 1. If desired later, you can run Option 2 at any time." --button1text "Display name only" --button2text "Complete adjustment" --infobuttontext "Cancel" --height "$dialogHeight")

dialogExitCode=$?
echo "DEBUG: dialog command exit code: '$dialogExitCode'" >&2
echo "DEBUG: mainChoice value: '$mainChoice'" >&2

# Initialize confirmation flag
CONFIRMED_COMPLETE_ADJUSTMENT=false

echo "DEBUG: dialogExitCode: '$dialogExitCode'"
echo "DEBUG: mainChoice exit code: '$mainChoice'"

# Process user choice based on exit code
if [[ "$dialogExitCode" == "0" ]]; then
    # Button 1: Display name only (exit code 0)
    echo "USER CHOICE: Adjust display name only"
    
    # Use the target display name we already determined
    displayName="$targetDisplayName"
    
    echo "DEBUG: Final displayName: '$displayName'" >&2
    perform_display_name_only "$displayName"
    exit 0

elif [[ "$dialogExitCode" == "2" ]]; then
    # Button 2: Complete adjustment - need confirmation (exit code 2 with 3-button layout!)
    echo "USER CHOICE: Complete adjustment requested - showing confirmation"
    
    # Show confirmation dialog for complete adjustment
    confirmDialog=$(dialog_command --message "# WARNING: Confirm complete adjustment<br><br>**You have chosen the complete adjustment.**<br><br>**What will happen:**<br>1. Automatic logout<br>2. Display name will be set to: **${targetDisplayName}**<br>3. Username will be adjusted: **$currentUser** → **$newUser**<br>4. Home folder will be renamed: **/Users/$currentUser** → **/Users/$newUser**<br>5. All files and settings moved automatically<br>6. **Automatic restart for clean completion**<br><br>**After the restart:**<br>• Use **$newUser** for login<br>• Password remains unchanged<br>• Jamf Connect continues to work<br>• Home folder path: **/Users/$newUser**<br>• All scripts will find files at correct path<br><br>**WARNING: This option requires a logout and restart!**" --button1text "Execute now" --button2text "Cancel" --height 650)
    
    confirmExitCode=$?
    echo "DEBUG: confirmDialog exit code: '$confirmExitCode'" >&2
    
    if [[ "$confirmExitCode" == "0" ]]; then
        # User clicked "Execute now" - continue with complete adjustment
        echo "USER CONFIRMED: Proceeding with complete adjustment"
        CONFIRMED_COMPLETE_ADJUSTMENT="true"
        # Continue to execution below after all if-elif-else blocks
    elif [[ "$confirmExitCode" == "1" ]]; then
        # User clicked "Cancel" in confirmation dialog
        echo "USER CANCELLED: Complete adjustment cancelled via Cancel button"
        show_info "Complete adjustment cancelled. No changes made.<br><br>You can run the adjustment again via Self Service at any time."
        exit 0
    else
        # User closed dialog or other exit code
        echo "USER CANCELLED: Complete adjustment cancelled (dialog closed, exit code: $confirmExitCode)"
        show_info "Complete adjustment cancelled. No changes made.<br><br>You can run the adjustment again via Self Service at any time."
        exit 0
    fi

elif [[ "$dialogExitCode" == "3" || "$dialogExitCode" == "1" ]]; then
    # Info button (Cancel) or unexpected exit code 1: Cancel (exit code 3 or 1)
    echo "USER CHOICE: Process cancelled"
    show_info "Process cancelled. No changes made.<br><br>You can run the adjustment again via Self Service at any time."
    exit 0

else
    # Fallback for unexpected codes (including empty/ESC or window close)
    echo "DEBUG: Unexpected dialogExitCode: '$dialogExitCode', treating as cancel"
    show_info "Process cancelled. No changes made.<br><br>You can run the adjustment again via Self Service at any time."
    exit 0
fi

# Check if complete adjustment was confirmed
if [[ "$CONFIRMED_COMPLETE_ADJUSTMENT" != "true" ]]; then
    echo "No complete adjustment confirmed - script should have exited already"
    show_info "Process cancelled. No changes made.<br><br>You can run the adjustment again via Self Service at any time."
    exit 0
fi

# ==== SHOW PROGRESS DIALOG FOR PRE-LOGOUT ACTIONS ====
commandFile="/var/tmp/dialog_prework.log"

echo "Starting prework dialog..." | tee -a /var/log/username_adjustment.log

dialog_command --message "## Preparing Adjustments

**Please wait while we prepare your system...**

• Checking display name  
• Preparing system updates  

**This will take a moment...**" --progress 10 --button1text "none" --moveable --ontop --height 400 --commandfile "$commandFile" &
preworkDialogPID=$!

echo "Dialog started with PID: $preworkDialogPID" | tee -a /var/log/username_adjustment.log

sleep 3

# ==== SET DISPLAY NAME FIRST (BEFORE LOGOUT) ====
echo "=== DISPLAY NAME CHANGE ===" | tee -a /var/log/username_adjustment.log
echo "progress: 30" >> "$commandFile"
echo "progresstext: Setting display name..." >> "$commandFile"
echo "message: ## Preparing Adjustments<br><br>**Setting display name...**<br><br>• Display name: **$targetDisplayName**<br>• Status: Working..." >> "$commandFile"

sleep 2

if [[ -z "$targetDisplayName" ]]; then
    echo "ERROR: targetDisplayName is EMPTY!" | tee -a /var/log/username_adjustment.log
    echo "quit:" >> "$commandFile"
    rm -f "$commandFile"
    exit 1
fi

echo "Setting display name to: $targetDisplayName" | tee -a /var/log/username_adjustment.log

# Set RealName (EXACTLY like in simple adjustment!)
dscl . -change "/Users/${currentUser}" RealName "" "$targetDisplayName" 2>/dev/null || \
dscl . -create "/Users/${currentUser}" RealName "$targetDisplayName"

echo "Display name command executed" | tee -a /var/log/username_adjustment.log

# Verify the change
verifyRealName=$(dscl . -read "/Users/${currentUser}" RealName 2>/dev/null | sed '1d' | tr -d '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
echo "Display name is now: '$verifyRealName'" | tee -a /var/log/username_adjustment.log

sleep 2

# ==== GET EMAIL FROM JAMF CONNECT STATE FOR JAMF RECON ====
echo "progress: 60" >> "$commandFile"
echo "progresstext: Updating Jamf inventory..." >> "$commandFile"
echo "message: ## Preparing Adjustments<br><br>**Updating Jamf inventory...**<br><br>• Display name: ✓ **$targetDisplayName**<br>• Syncing with Jamf..." >> "$commandFile"

sleep 2

echo "=== UPDATING JAMF (before logout) ===" | tee -a /var/log/username_adjustment.log

# Get email from Jamf Connect State Plist (most current!)
jamfConnectStateFile="/Users/${currentUser}/Library/Preferences/com.jamf.connect.state.plist"
targetEmail=""

if [[ -f "$jamfConnectStateFile" ]]; then
    # Try preferred_username
    targetEmail=$(sudo -u "$currentUser" /usr/libexec/PlistBuddy -c "Print :IdToken:preferred_username" "$jamfConnectStateFile" 2>/dev/null)
    
    if [[ -z "$targetEmail" || "$targetEmail" == "Does Not Exist" ]]; then
        # Try upn
        targetEmail=$(sudo -u "$currentUser" /usr/libexec/PlistBuddy -c "Print :IdToken:upn" "$jamfConnectStateFile" 2>/dev/null)
    fi
    
    if [[ -z "$targetEmail" || "$targetEmail" == "Does Not Exist" ]]; then
        # Try email
        targetEmail=$(sudo -u "$currentUser" /usr/libexec/PlistBuddy -c "Print :IdToken:email" "$jamfConnectStateFile" 2>/dev/null)
    fi
fi

# Fallback to current email if Jamf Connect State not available
if [[ -z "$targetEmail" || "$targetEmail" == "Does Not Exist" ]]; then
    targetEmail="$currentEmail"
fi

echo "Target email for Jamf: $targetEmail" | tee -a /var/log/username_adjustment.log

if [[ -n "$targetEmail" && "$targetEmail" != "Does Not Exist" ]]; then
    /usr/local/bin/jamf recon -endUsername "$targetEmail" 2>&1 | tee -a /var/log/username_adjustment.log
    echo "Jamf update completed with: $targetEmail" | tee -a /var/log/username_adjustment.log
else
    echo "WARNING: No valid email found" | tee -a /var/log/username_adjustment.log
fi

sleep 2

# ==== CLOSE PREWORK DIALOG ====
echo "progress: 100" >> "$commandFile"
echo "progresstext: Preparation complete!" >> "$commandFile"
echo "message: ## Preparation Complete<br><br>**Completed:**<br>✓ Display name set<br>✓ Jamf inventory updated<br><br>**Preparing next steps...**" >> "$commandFile"

sleep 3

echo "quit:" >> "$commandFile"
rm -f "$commandFile" 2>/dev/null

# ==== CHECK IF USERNAME CHANGE IS NEEDED ====
needsUsernameChange=false
if [[ "$newUser" != "$currentUser" ]]; then
    needsUsernameChange=true
    echo "Username change needed: $currentUser → $newUser" | tee -a /var/log/username_adjustment.log
else
    echo "Username already correct: $currentUser" | tee -a /var/log/username_adjustment.log
fi

# ==== SHOW CONFIRMATION DIALOG WITH COUNTDOWN ====
if [[ "$needsUsernameChange" == "true" ]]; then
    confirmMessage="# Logout and Adjustment

**Completed:**
✓ Display name: **${targetDisplayName}**
✓ Jamf inventory updated

**After logout:**
• Username: **$currentUser** → **$newUser**
• Home folder: /Users/$currentUser → /Users/$newUser

**System will restart automatically.**

**Logging out in 10 seconds...**"
else
    confirmMessage="# Adjustments Complete

**Completed:**
✓ Display name: **${targetDisplayName}**
✓ Jamf inventory updated
✓ Username already correct: **$currentUser**

**System will restart in 10 seconds...**"
fi

dialog_command --message "$confirmMessage" --button1text "none" --moveable --ontop --height 450 &
confirmDialogPID=$!

# Countdown
for i in {10..1}; do
    sleep 1
done

kill -9 $confirmDialogPID 2>/dev/null

# ==== IF NO USERNAME CHANGE NEEDED, JUST RESTART ====
if [[ "$needsUsernameChange" == "false" ]]; then
    echo "=== NO USERNAME CHANGE NEEDED - RESTARTING ===" | tee -a /var/log/username_adjustment.log
    
    pkill -9 -f "Dialog.app" 2>/dev/null
    
    echo "Executing restart..." | tee -a /var/log/username_adjustment.log
    /sbin/shutdown -r now "Adjustments completed" 2>&1 | tee -a /var/log/username_adjustment.log
    
    # Wait and try fallback methods
    sleep 10
    /sbin/reboot 2>&1 | tee -a /var/log/username_adjustment.log
    sleep 10
    osascript -e 'tell app "System Events" to restart' 2>/dev/null
    
    # Keep script alive
    while true; do sleep 60; done
fi

# ==== LOG OUT USER ====
echo "=== STARTING LOGOUT ===" | tee -a /var/log/username_adjustment.log

loginCheck=$(ps -Ajc | grep ${currentUser} | grep loginwindow | awk '{print $2}')
if [[ "$loginCheck" ]]; then
  echo "Logging out user..." | tee -a /var/log/username_adjustment.log
  launchctl bootout gui/$(id -u ${currentUser})
  sleep 3
  echo "User logged out" | tee -a /var/log/username_adjustment.log
fi

# ==== ACCOUNT RENAMING ====
echo "=== CHANGING USERNAME ===" | tee -a /var/log/username_adjustment.log
echo "From: $currentUser" | tee -a /var/log/username_adjustment.log
echo "To: $newUser" | tee -a /var/log/username_adjustment.log

dscl . -change "/Users/${currentUser}" RecordName "$currentUser" "$newUser" 2>&1 | tee -a /var/log/username_adjustment.log
if [[ $? -eq 0 ]]; then
    echo "SUCCESS: Username changed" | tee -a /var/log/username_adjustment.log
else
    echo "ERROR: Username change failed" | tee -a /var/log/username_adjustment.log
fi

# ==== HOME PATH ====
echo "=== UPDATING HOME PATH ===" | tee -a /var/log/username_adjustment.log

currentHomeDir="/Users/${currentUser}"
dscl . -change "/Users/${newUser}" NFSHomeDirectory "$currentHomeDir" "/Users/$newUser" 2>&1 | tee -a /var/log/username_adjustment.log
if [[ $? -eq 0 ]]; then
    echo "SUCCESS: Home path updated" | tee -a /var/log/username_adjustment.log
else
    echo "ERROR: Home path update failed" | tee -a /var/log/username_adjustment.log
fi

# ==== MOVE FOLDER ====
echo "=== MOVING HOME FOLDER ===" | tee -a /var/log/username_adjustment.log

if [[ -d "$currentHomeDir" && ! -d "/Users/$newUser" ]]; then
    echo "Moving folder from $currentHomeDir to /Users/$newUser" | tee -a /var/log/username_adjustment.log
    mv "$currentHomeDir" "/Users/$newUser" 2>&1 | tee -a /var/log/username_adjustment.log
    if [[ $? -eq 0 ]]; then
        echo "SUCCESS: Folder moved" | tee -a /var/log/username_adjustment.log
    else
        echo "ERROR: Folder move failed" | tee -a /var/log/username_adjustment.log
    fi
else
    echo "Folder already at correct location" | tee -a /var/log/username_adjustment.log
fi

# ==== PERMISSIONS ====
echo "=== SETTING PERMISSIONS ===" | tee -a /var/log/username_adjustment.log

if [[ -d "/Users/$newUser" ]]; then
    chown -R "$newUser:" "/Users/$newUser" 2>&1 | tee -a /var/log/username_adjustment.log
    echo "SUCCESS: Permissions set" | tee -a /var/log/username_adjustment.log
fi

# ==== RESTART ====
echo "=== EXECUTING RESTART ===" | tee -a /var/log/username_adjustment.log
echo "All changes completed" | tee -a /var/log/username_adjustment.log

pkill -9 -f "Dialog.app" 2>/dev/null

echo "Method 1: shutdown -r now" | tee -a /var/log/username_adjustment.log
/sbin/shutdown -r now "Username adjustment completed" 2>&1 | tee -a /var/log/username_adjustment.log

sleep 10

echo "Method 2: reboot" | tee -a /var/log/username_adjustment.log
/sbin/reboot 2>&1 | tee -a /var/log/username_adjustment.log

sleep 10

echo "Method 3: osascript restart" | tee -a /var/log/username_adjustment.log
osascript -e 'tell app "System Events" to restart' 2>/dev/null

# Keep script alive
while true; do
    sleep 60
done

exit 0