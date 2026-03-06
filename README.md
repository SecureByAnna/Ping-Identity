# PingOne User Audit Script

A PowerShell script to audit user login activity in PingOne environments. Generates a CSV report showing last login times, inactive users, and users who have never logged in.

## Features

- Retrieves all users from a PingOne environment
- Reports last sign-on date/time for each user
- Calculates days since last login
- Identifies users who have never logged in
- Shows account status (OK, LOCKED, etc.) and enabled state
- Supports all PingOne regions (NA, EU, CA, AP, AU, SG)
- Handles pagination for large user bases
- PowerShell 5.1 compatible (no PS7 required)

## Requirements

- PowerShell 5.1 or higher
- PingOne Worker Application with **Identity Data Admin** role

## Setup

1. In PingOne Admin Console, go to **Applications → Applications**
2. Create or select a Worker application
3. Go to the **Roles** tab and ensure **Identity Data Admin** role is assigned
4. Go to **Configuration** tab, scroll down, and click **Get Access Token**
5. Copy the token for use with this script

## Usage

```powershell
# Store token in a variable first (avoids command-line token corruption)
$token = @'
eyJhbGciOiJSUzI1Ni...paste-your-full-token-here...
'@

# Run the script
.\PingOne-UserAudit.ps1 -EnvironmentId "your-environment-id" -AccessToken $token
```

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-EnvironmentId` | Yes | Your PingOne environment ID (GUID) |
| `-AccessToken` | Yes | Bearer token from PingOne |
| `-Region` | No | PingOne region: NA, EU, CA, AP, AU, SG (default: NA) |
| `-OutputFile` | No | Output CSV filename (default: pingone_user_audit.csv) |
| `-FilterUsername` | No | Filter to a specific username for testing |

### Examples

```powershell
# Basic usage (North America region)
.\PingOne-UserAudit.ps1 -EnvironmentId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -AccessToken $token

## Output

The script generates a CSV file with the following columns:

| Column | Description |
|--------|-------------|
| `username` | User's username |
| `email` | User's email address |
| `user_id` | PingOne user ID (GUID) |
| `created_at` | Account creation timestamp |
| `updated_at` | Last account update timestamp |
| `last_sign_on` | Last successful login timestamp |
| `days_since_login` | Number of days since last login |
| `never_logged_in` | TRUE if user has never logged in |
| `enabled` | TRUE if account is enabled |
| `account_status` | Account status (OK, LOCKED, PENDING) |

### Account Status Values

| Status | Meaning |
|--------|---------|
| OK | Account is active and can authenticate normally |
| LOCKED | Account is locked (too many failed attempts) |
| PENDING | Account is pending activation |

## Troubleshooting

### "All users show as never logged in"

If `lastSignOn` is empty for all users:
1. Verify your Worker app has **Identity Data Admin** role
2. Contact PingOne support - `lastSignOn` tracking may need to be enabled
3. Check if users authenticate through an external IdP (may not update this field)

### Token errors on command line

Special characters in tokens (`+`, `/`, `=`) can get corrupted on the command line. Always use a here-string variable:

```powershell
$token = @'
your-token-here
'@
```

### API authentication errors

- Verify your token hasn't expired (get a fresh one)
- Check that the Worker app has the correct role assigned
- Ensure you're using the correct region parameter

## Security Notes

⚠️ **Important:**
- Never commit access tokens to version control
- The output CSV contains user data - handle according to your organization's data policies
- For automation, use environment variables or secure vaults for token storage
- Access tokens are short-lived; generate fresh tokens as needed

## License

MIT License - See [LICENSE](LICENSE) file

## Contributing

Contributions welcome! Please open an issue or submit a pull request.

## Acknowledgments

Developed with assistance from PingOne Support documentation.
