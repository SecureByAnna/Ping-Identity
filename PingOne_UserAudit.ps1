<#
.SYNOPSIS
    PingOne User Audit - Exports a CSV with last login info per user.

.DESCRIPTION
    Retrieves all users from a PingOne environment and generates a report showing:
    - Last sign-on date/time
    - Days since last login
    - Users who have never logged in
    - Account status and enabled state

    Requirements:
    - PingOne Worker Application with "Identity Data Admin" role
    - PowerShell 5.1 or higher

    HOW TO GET YOUR ACCESS TOKEN:
      1. Go to Applications -> Applications in PingOne Admin Console
      2. Select your Worker app
      3. Verify it has "Identity Data Admin" role (Roles tab)
      4. Configuration tab -> scroll to bottom -> click "Get Access Token"
      5. Copy the token

.PARAMETER EnvironmentId
    Your PingOne environment ID (GUID)

.PARAMETER AccessToken
    Your PingOne access token - USE A VARIABLE, not direct command line!
    
    Example:
      $token = @'
      eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
      '@
      
      .\PingOne-UserAudit.ps1 -EnvironmentId "your-env-id" -AccessToken $token

.PARAMETER Region
    Optional. PingOne region. Values: NA, EU, CA, AP, AU, SG (default: NA)

.PARAMETER OutputFile
    Optional. Output CSV filename. Default: pingone_user_audit.csv

.PARAMETER FilterUsername
    Optional. Filter to a specific username (for testing)
    Example: -FilterUsername "john.doe@company.com"

.EXAMPLE
    # Store token in variable first (recommended to avoid command-line issues)
    $token = @'
    eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...your-full-token-here...
    '@
    .\PingOne-UserAudit.ps1 -EnvironmentId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -AccessToken $token

.EXAMPLE
    # Test with a single user first
    .\PingOne-UserAudit.ps1 -EnvironmentId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -AccessToken $token -FilterUsername "test@example.com"

.EXAMPLE
    # Specify a different region
    .\PingOne-UserAudit.ps1 -EnvironmentId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -AccessToken $token -Region EU

.NOTES
    Author: Community Contribution
    Version: 1.0.0
    
    Security Notes:
    - Never commit access tokens to version control
    - Use environment variables or secure vaults for tokens in automation
    - The output CSV contains user data - handle according to your data policies

.LINK
    https://developer.pingidentity.com/pingone-api/platform/users/users-1/read-all-users.html
#>

param(
    [Parameter(Mandatory = $true)]
    [string] $EnvironmentId,

    [Parameter(Mandatory = $true)]
    [string] $AccessToken,

    [ValidateSet("NA", "EU", "CA", "AP", "AU", "SG")]
    [string] $Region = "NA",

    [string] $OutputFile = "pingone_user_audit.csv",

    [string] $FilterUsername = ""
)

$ErrorActionPreference = "Stop"

# Region to API domain mapping
$RegionDomains = @{
    "NA" = "api.pingone.com"
    "EU" = "api.pingone.eu"
    "CA" = "api.pingone.ca"
    "AP" = "api.pingone.asia"
    "AU" = "api.pingone.com.au"
    "SG" = "api.pingone.sg"
}

function Write-Log {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message" -ForegroundColor $Color
}

# Setup
$ApiDomain = $RegionDomains[$Region]
$ApiBase = "https://$ApiDomain/v1/environments/$EnvironmentId"

Write-Log "PingOne User Audit Script"
Write-Log "========================="
Write-Log "Region: $Region"
Write-Log "API Base: $ApiBase"
Write-Log ""

# Clean token (remove any whitespace/newlines that might have crept in)
$AccessToken = $AccessToken.Trim()

$headers = @{
    "Authorization" = "Bearer $AccessToken"
    "Content-Type"  = "application/json"
}

# Build the users URL
$usersUrl = "$ApiBase/users?limit=100"

# Add filter if specified (per PingOne support's example)
if ($FilterUsername -ne "") {
    $filter = "username eq `"$FilterUsername`""
    $encodedFilter = [Uri]::EscapeDataString($filter)
    $usersUrl = "$ApiBase/users?filter=$encodedFilter"
    Write-Log "Filtering for username: $FilterUsername" "Yellow"
}

# Fetch all users with pagination
Write-Log "Fetching users from PingOne..."

$allUsers = [System.Collections.Generic.List[object]]::new()
$nextUrl = $usersUrl
$pageCount = 0

while ($nextUrl) {
    $pageCount++
    Write-Log "  Fetching page $pageCount..." "Gray"
    
    try {
        $response = Invoke-RestMethod -Method Get -Uri $nextUrl -Headers $headers
    }
    catch {
        $errorMsg = $_.Exception.Message
        
        # Try to get response body
        if ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($stream)
                $errorBody = $reader.ReadToEnd()
                $reader.Close()
                $errorMsg = $errorBody
            } catch {}
        }
        
        Write-Log "ERROR: API call failed" "Red"
        Write-Log "URL: $nextUrl" "Red"
        Write-Log "Error: $errorMsg" "Red"
        exit 1
    }
    
    # Extract users from response
    if ($response._embedded -and $response._embedded.users) {
        foreach ($user in $response._embedded.users) {
            $allUsers.Add($user)
        }
    }
    
    # Check for next page
    $nextUrl = $null
    if ($response._links -and $response._links.next) {
        $nextUrl = $response._links.next.href
    }
}

Write-Log "Retrieved $($allUsers.Count) users" "Green"
Write-Log ""

# Process users and build report
$report = [System.Collections.Generic.List[PSCustomObject]]::new()

$usersWithLogin = 0
$usersNeverLogged = 0

Write-Log "Processing users..."

foreach ($user in $allUsers) {
    # Get basic info
    $userId = $user.id
    $username = $user.username
    
    # Get email (try multiple possible properties)
    $email = ""
    if ($user.PSObject.Properties["email"] -and $user.email) {
        $email = $user.email
    }
    elseif ($user.PSObject.Properties["primaryEmail"] -and $user.primaryEmail) {
        $email = $user.primaryEmail
    }
    elseif ($username -match "@") {
        $email = $username
    }
    
    # Get dates
    $createdAt = if ($user.PSObject.Properties["createdAt"]) { $user.createdAt } else { "" }
    $updatedAt = if ($user.PSObject.Properties["updatedAt"]) { $user.updatedAt } else { "" }
    
    # Get lastSignOn - check both possible property formats
    $lastSignOn = ""
    if ($user.PSObject.Properties["lastSignOn"] -and $user.lastSignOn) {
        # lastSignOn might be an object with 'at' property or a direct timestamp
        if ($user.lastSignOn -is [string]) {
            $lastSignOn = $user.lastSignOn
        }
        elseif ($user.lastSignOn.PSObject.Properties["at"]) {
            $lastSignOn = $user.lastSignOn.at
        }
    }
    
    # Also check lastSignOnAt (alternative property name)
    if ($lastSignOn -eq "" -and $user.PSObject.Properties["lastSignOnAt"] -and $user.lastSignOnAt) {
        $lastSignOn = $user.lastSignOnAt
    }
    
    # Check for enabled status
    $enabled = if ($user.PSObject.Properties["enabled"]) { $user.enabled } else { "" }
    
    # Account status
    $accountStatus = ""
    if ($user.PSObject.Properties["account"] -and $user.account) {
        if ($user.account.PSObject.Properties["status"]) {
            $accountStatus = $user.account.status
        }
    }
    
    # Calculate days since login and never_logged_in flag
    $daysSinceLogin = ""
    $neverLoggedIn = $true
    
    if ($lastSignOn -ne "") {
        $neverLoggedIn = $false
        $usersWithLogin++
        
        try {
            $lastSignOnDate = [DateTime]::Parse($lastSignOn, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $daysSinceLogin = [math]::Floor(((Get-Date) - $lastSignOnDate).TotalDays)
        }
        catch {
            # If date parsing fails, just use the raw value
        }
    }
    else {
        $usersNeverLogged++
    }
    
    # Add to report
    $report.Add([PSCustomObject]@{
        username         = $username
        email            = $email
        user_id          = $userId
        created_at       = $createdAt
        updated_at       = $updatedAt
        last_sign_on     = $lastSignOn
        days_since_login = $daysSinceLogin
        never_logged_in  = $neverLoggedIn
        enabled          = $enabled
        account_status   = $accountStatus
    })
}

# Sort by last_sign_on (users with logins first, then never logged in)
$report = $report | Sort-Object -Property @{Expression={$_.never_logged_in}; Ascending=$true}, @{Expression={$_.last_sign_on}; Descending=$true}

# Export to CSV
$report | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

# Summary
Write-Log ""
Write-Log "========================================" "White"
Write-Log "           SUMMARY" "White"
Write-Log "========================================" "White"
Write-Log "Total users:           $($allUsers.Count)" "White"
Write-Log "Users with lastSignOn: $usersWithLogin" "Green"
Write-Log "Never logged in:       $usersNeverLogged" "Yellow"
Write-Log "========================================" "White"
Write-Log ""
Write-Log "CSV saved to: $OutputFile" "Green"

# If all users show as never logged in, display warning
if ($usersNeverLogged -eq $allUsers.Count -and $allUsers.Count -gt 0) {
    Write-Log ""
    Write-Log "WARNING: All users show as 'never logged in'!" "Red"
    Write-Log "The lastSignOn property is not populated for any user." "Red"
    Write-Log ""
    Write-Log "This may indicate:" "Yellow"
    Write-Log "  1. lastSignOn tracking is not enabled for this environment" "Yellow"
    Write-Log "  2. A configuration setting needs to be enabled by PingOne support" "Yellow"
    Write-Log "  3. Users are authenticating through an external IdP that doesn't update this field" "Yellow"
    Write-Log ""
    Write-Log "Please contact PingOne support with this output." "Yellow"
}

# Show sample of results
Write-Log ""
Write-Log "Sample results (first 5 users):" "Cyan"
$report | Select-Object -First 5 | Format-Table username, last_sign_on, never_logged_in, created_at -AutoSize
