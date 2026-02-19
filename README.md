# Twingate + AAP User Provisioning

Automated user provisioning workflow combining Twingate user creation with AAP (Ansible Automation Platform) job template access management, and optional Jira ticket closure.

## Overview

This project automates the complete user onboarding process:

1. **Twingate User Creation**: Creates users in Twingate from a CSV file and assigns them to appropriate groups
2. **AAP Access Grant**: Grants execute permissions on AAP job templates to provisioned users
3. **Jira Ticket Closure** (Optional): Automatically closes Jira tickets after successful provisioning

## Prerequisites

- Ansible 2.10+
- Python 3.6+
- Twingate API access (API key required)
- AAP instance access (token or username/password required)
- Network/API connectivity to both Twingate and AAP
- Jira API access (email + API token - optional, for ticket closure feature)

## Quick Start

### 1. Install Dependencies

```bash
ansible-galaxy collection install -r requirements.yml
```

### 2. Configure Environment

Copy the example environment file and edit with your credentials:

```bash
cp .env.example .env
# Edit .env with your actual API keys and URLs
```

**Note:** The `run.sh` script automatically loads and exports variables from `.env`. If running playbooks directly without `run.sh`, you must export variables first:

```bash
set -a && source .env && set +a
```

This command does three things:
- `set -a` - Makes all variables automatically export to child processes
- `source .env` - Reads and executes the `.env` file
- `set +a` - Turns off automatic export

Without this, the playbooks won't have access to `TWINGATE_API_KEY`, `TOWER_HOST`, `TOWER_OAUTH_TOKEN`, etc.

Required environment variables:
- `TWINGATE_API_KEY` - Your Twingate API key
- `TOWER_HOST` - Your AAP instance URL (e.g., https://aap.example.com)
- `TOWER_OAUTH_TOKEN` - Your AAP authentication token (or use TOWER_USERNAME/TOWER_PASSWORD)

Optional environment variables (for Jira integration - choose ONE authentication method):
- **Method 1 (Recommended for Red Hat Jira):** Personal Access Token
  - `JIRA_PAT` - Your Jira Personal Access Token (get from https://issues.redhat.com → Profile → Personal Access Tokens)
- **Method 2 (Fallback for Jira Cloud):** Email + API Token
  - `JIRA_EMAIL` - Your Jira email address (e.g., user@redhat.com)
  - `JIRA_API_TOKEN` - Your Jira API token (get from https://id.atlassian.com/manage-profile/security/api-tokens)
- **Both methods:**
  - `JIRA_BASE_URL` - Jira instance URL (default: https://issues.redhat.com)

**Note:** If `JIRA_PAT` is set, it will be used and email+token will be ignored. If no Jira credentials are set, the Jira integration is automatically skipped without errors.

**AAP Users:** When running as AAP jobs, if you have a custom credential that injects `vaultkv_secret`, it will automatically be used as the Jira PAT. No additional configuration needed.

### 3. Prepare User Data

Place your user CSV file in the `data/` directory. The default file is `data/usernames-devqe.csv`.

**CSV Format (headerless):**
```
username,email@example.com,DEVQE,First,Last,IBMC-groupname,DPP-00000
```

- Column 1: Username/Kerberos ID (used for AAP)
- Column 2: Email address (used for Twingate)
- Column 6: Twingate group name (optional)
- Column 7: Jira ticket ID (e.g., DPP-00000) - used for automatic ticket closure (optional)

**Important:** The CSV uses username (column 1) for AAP, email (column 2) for Twingate, and ticket ID (column 7) for Jira integration.

### Input Methods

The workflow supports two input methods with automatic fallback:

1. **CSV File** (default) - Process multiple users from a file
   - Default: `data/usernames-devqe.csv`
   - Override with `-e "csv_path=/path/to/file.csv"`
   - If the file doesn't exist, the playbook will fail with a helpful error message

2. **Inline CSV Line** - Process a single user from command line
   - Pass with `-e 'csv_line=username,email,DEVQE,First,Last,GroupName,DPP-00000'`
   - Useful for single user provisioning or scripting
   - When provided, the CSV file is ignored (even if it exists)
   - Automatically used if CSV file is not found
   - **Auto-sanitization**: Can paste echo commands directly - the playbook automatically strips wrappers:
     - Input: `echo 'flast,flast@redhat.com,DEVQE,First,Last,IBMC-devqe,DPP-00000' >> file.csv`
     - Cleaned: `flast,flast@redhat.com,DEVQE,First,Last,IBMC-devqe,DPP-00000`

**Note:** If the CSV file is not found and no inline CSV data is provided, the playbook will fail with a clear error message explaining both input options.

### 4. Run Complete Workflow

Using the helper script with default DEVQE templates:
```bash
./run.sh full
```

Or specify custom templates:
```bash
./run.sh full "Template1,Template2,Template3"
```

Or run playbook directly:
```bash
ansible-playbook playbooks/main.yml \
  -e "aap_template_names=Template1,Template2,Template3"
```

**Default Templates:** The `./run.sh full` command uses these templates by default:
- vSphere-Nested-DEVQE
- vSphere-Nested-DEVQE-static
- vSphere-Nested-DEVQE-static-autoscript
- vSphere-Nested-DEVQE-vSAN
- vSphere-Nested-DEVQE-vSphere-9
- vSphere-Nested-DEVQE-vSphere-9-static
- vSphere-Nested-DEVQE-vSphere-9-static-autoscript
- vSphere-Nested-DEVQE-vSAN-vsphere-9

## Usage Examples

### Run Complete Workflow

**Simplest way** - Use the helper script with default templates:
```bash
./run.sh full
```

**Custom templates:**
```bash
./run.sh full "vSphere-Nested-DEVQE,vSphere-Nested-DEVQE-static"
```

**Using ansible-playbook directly (equivalent to `./run.sh full`):**
```bash
# First, export environment variables from .env
set -a && source .env && set +a

# Then run the playbook with the default templates
ansible-playbook playbooks/main.yml \
  -e "aap_template_names=vSphere-Nested-DEVQE,vSphere-Nested-DEVQE-static,vSphere-Nested-DEVQE-static-autoscript,vSphere-Nested-DEVQE-vSAN,vSphere-Nested-DEVQE-vSphere-9,vSphere-Nested-DEVQE-vSphere-9-static,vSphere-Nested-DEVQE-vSphere-9-static-autoscript,vSphere-Nested-DEVQE-vSAN-vsphere-9"
```

**One-liner version:**
```bash
set -a && source .env && set +a && ansible-playbook playbooks/main.yml -e "aap_template_names=vSphere-Nested-DEVQE,vSphere-Nested-DEVQE-static,vSphere-Nested-DEVQE-static-autoscript,vSphere-Nested-DEVQE-vSAN,vSphere-Nested-DEVQE-vSphere-9,vSphere-Nested-DEVQE-vSphere-9-static,vSphere-Nested-DEVQE-vSphere-9-static-autoscript,vSphere-Nested-DEVQE-vSAN-vsphere-9"
```

**Note:** If you've already exported your environment variables manually, you can skip the `set -a && source .env && set +a` part and just run:
```bash
ansible-playbook playbooks/main.yml \
  -e "aap_template_names=vSphere-Nested-DEVQE,vSphere-Nested-DEVQE-static,vSphere-Nested-DEVQE-static-autoscript,vSphere-Nested-DEVQE-vSAN,vSphere-Nested-DEVQE-vSphere-9,vSphere-Nested-DEVQE-vSphere-9-static,vSphere-Nested-DEVQE-vSphere-9-static-autoscript,vSphere-Nested-DEVQE-vSAN-vsphere-9"
```

**Using inline CSV line instead of a file:**

You can pass a single CSV line directly on the command line instead of using the CSV file:

```bash
set -a && source .env && set +a

ansible-playbook playbooks/main.yml \
  -e 'csv_line=flast,flast@redhat.com,DEVQE,First,Last,IBMC-devqe,DPP-00000' \
  -e "aap_template_names=vSphere-Nested-DEVQE,vSphere-Nested-DEVQE-static"
```

This will:
1. Create the user `flast@redhat.com` in Twingate and add to group `IBMC-devqe`
2. Grant user `flast` execute access on the specified AAP templates

**Note:** When using `csv_line`, the CSV file is ignored. The format is the same as the CSV file format:
```
username,email,DEVQE,First,Last,GroupName,DPP-00000
```

### Enable Jira Ticket Closure

By default, Jira integration is **disabled**. To enable automatic ticket closure after successful provisioning:

**Enable Jira with environment variables (Method 1 - PAT, recommended for Red Hat Jira):**
```bash
# Set Jira PAT credential
export JIRA_PAT=your_personal_access_token

# Run workflow with Jira enabled
ansible-playbook playbooks/main.yml \
  -e "jira_enabled=true" \
  -e "aap_template_names=Template1,Template2"
```

**Or with Email + API Token (Method 2 - fallback for Jira Cloud):**
```bash
# Set Jira credentials
export JIRA_EMAIL=your_email@redhat.com
export JIRA_API_TOKEN=your_jira_api_token

# Run workflow with Jira enabled
ansible-playbook playbooks/main.yml \
  -e "jira_enabled=true" \
  -e "aap_template_names=Template1,Template2"
```

**Pass credentials via command line (alternative to environment variables):**
```bash
# Using PAT via -e flag
ansible-playbook playbooks/main.yml \
  -e "jira_enabled=true" \
  -e "jira_pat=your_personal_access_token" \
  -e "aap_template_names=Template1,Template2"

# Using Email + API Token via -e flags
ansible-playbook playbooks/main.yml \
  -e "jira_enabled=true" \
  -e "jira_email=your_email@redhat.com" \
  -e "jira_api_token=your_jira_api_token" \
  -e "aap_template_names=Template1,Template2"
```

**Credential Priority Order:**
1. Command-line extra vars (`-e jira_pat=...`) - Highest priority
2. Environment variables (`JIRA_PAT`, `JIRA_EMAIL`, etc.)
3. AAP custom credentials - Lowest priority

**One-liner with .env file:**
```bash
set -a && source .env && set +a && ansible-playbook playbooks/main.yml \
  -e "jira_enabled=true" \
  -e "aap_template_names=Template1,Template2"
```

**Using helper script (requires setting JIRA_ENABLED=true in .env or exporting it):**
```bash
export JIRA_ENABLED=true
./run.sh full
```

**What happens when Jira is enabled:**
1. After both Twingate and AAP tasks complete successfully
2. Extracts Jira ticket IDs from CSV column 7 (e.g., DPP-00000)
3. Adds a comment to each ticket documenting the provisioning
4. Transitions the ticket to closed/done status

**Note:** If Jira update fails, a warning is logged but the playbook continues. User provisioning success is not dependent on Jira ticket closure.

**To disable Jira integration:**
- Simply omit the `-e "jira_enabled=true"` flag (default behavior)
- Or explicitly disable: `-e "jira_enabled=false"`
- Or use tags: `--skip-tags jira`

### Run Twingate Only

Create users in Twingate without granting AAP access:

**From CSV file:**
```bash
ansible-playbook playbooks/twingate_create_users.yml \
  -e "csv_path={{ playbook_dir }}/../data/usernames-devqe.csv"
```

**From inline CSV line:**
```bash
set -a && source .env && set +a

ansible-playbook playbooks/twingate_create_users.yml \
  -e 'csv_line=flast,flast@redhat.com,DEVQE,First,Last,IBMC-devqe,DPP-00000'
```

### Run AAP Access Only

Grant access to a single user on specific templates (use kerberos ID/username, not email):

```bash
ansible-playbook playbooks/aap_grant_access.yml \
  -e "username=flast" \
  -e "template_name=vSphere-Nested-DEVQE-static"
```

Multiple templates:

```bash
ansible-playbook playbooks/aap_grant_access.yml \
  -e "username=flast" \
  -e "template_names=Template1,Template2,Template3"
```

Or use the helper script:

```bash
# Single template
./run.sh aap flast "vSphere-Nested-DEVQE-static"

# Multiple templates (comma-separated)
./run.sh aap flast "Template1,Template2,Template3"
```

### Use Tags for Selective Execution

Run only Twingate user creation:

```bash
ansible-playbook playbooks/main.yml --tags twingate
```

Run only AAP access granting:

```bash
ansible-playbook playbooks/main.yml --tags aap \
  -e "aap_template_names=Template1,Template2"
```

## Project Structure

```
.
├── ansible.cfg                      # Ansible configuration
├── data/                            # Input data files
│   └── usernames-devqe.csv         # User CSV input
├── inventory/
│   ├── hosts.ini                   # Inventory file
│   └── group_vars/
│       └── all.yml                 # AAP controller variables
├── playbooks/
│   ├── main.yml                    # Master orchestration playbook
│   ├── twingate_create_users.yml   # Twingate user creation
│   ├── aap_grant_access.yml        # AAP access grant (single user)
│   └── aap_grant_access_task.yml   # AAP task (called in loop)
├── tasks/
│   └── twingate/                   # Twingate task files
├── vars/
│   └── twingate_defaults.yml       # Twingate configuration
├── requirements.yml                # Collection dependencies
├── .env.example                    # Environment variables template
└── README.md                       # This file
```

## Configuration

### Twingate Configuration

Edit `vars/twingate_defaults.yml` to set your Twingate subdomain:

```yaml
twingate_subdomain: "your-subdomain"  # for your-subdomain.twingate.com
```

### AAP Configuration

AAP settings are configured via environment variables in `inventory/group_vars/all.yml`:

- `controller_host` - AAP URL
- `controller_token` - Authentication token (recommended)
- `controller_username` / `controller_password` - Alternative auth
- `controller_verify_ssl` - SSL certificate verification (true/false)

### Running as AAP Job

When running these playbooks **as AAP jobs** (executing within AAP, not just targeting it), you need to configure both Twingate and AAP/Tower credentials:

**AAP/Tower Credentials (Built-in):**

The playbooks automatically use AAP's built-in credential injection:

1. **Create or Select AAP Credential**:
   - Use the built-in "Red Hat Ansible Automation Platform" credential type
   - Configure with target AAP instance URL, username, password, or OAuth token

2. **Attach to Job Template**:
   - Add the AAP credential to your job template
   - AAP automatically injects: `host`, `username`, `password`, `oauth_token`, `verify_ssl`
   - The playbooks automatically detect and use these variables (see `inventory/group_vars/all.yml`)

**Credential Loading Priority (for AAP controller connection):**
1. AAP credential injection: `host`, `username`, `password`, `oauth_token`, `verify_ssl` (for AAP job execution)
2. Environment variables: `TOWER_HOST`, `TOWER_USERNAME`, `TOWER_PASSWORD`, `TOWER_OAUTH_TOKEN`, `TOWER_VERIFY_SSL` (for local CLI runs)
3. Default values (fallback)

**Twingate API Key (Custom Credential):**

The playbooks automatically detect and use a custom credential for Twingate:

1. **Create Custom Credential Type** in AAP:
   - Name: `Twingate API Key`
   - Input Configuration:
     ```yaml
     fields:
       - id: custom_token
         type: string
         label: Twingate API Key
         secret: true
     required:
       - custom_token
     ```
   - Injector Configuration:
     ```yaml
     extra_vars:
       custom_token: '{{ custom_token }}'
     ```

2. **Create Credential** using the custom type:
   - Add your actual Twingate API key value

3. **Attach to Job Template**:
   - Add both the AAP credential and the Twingate custom credential to your job template
   - AAP will automatically inject all variables when the job runs

**API Key Loading Priority (for Twingate):**
1. Environment variable `TWINGATE_API_KEY` (for local CLI runs)
2. AAP custom credential `custom_token` (for AAP job execution)
3. `.env` file fallback (for local runs)

**Summary:** Just attach two credentials to your AAP job template (AAP platform credential + Twingate custom credential), and the playbooks handle everything automatically. No extra variables needed for credentials.

**AAP Job Template Extra Variables:**

When configuring the AAP job template, you can set these extra variables.

**Format 1: Comma-separated string (recommended for CLI)**
```yaml
csv_line: 'username,email,DEVQE,First,Last,GroupName,DPP-00000'
aap_template_names: 'Template1,Template2,Template3'
```

**Format 2: YAML list (recommended for AAP web UI)**
```yaml
csv_line: 'username,email,DEVQE,First,Last,GroupName,DPP-00000'
aap_template_names:
  - Template1
  - Template2
  - Template3
```

**Format 3: JSON array (also works in AAP web UI)**
```yaml
csv_line: 'username,email,DEVQE,First,Last,GroupName,DPP-00000'
aap_template_names: ["Template1","Template2","Template3"]
```

**Format 4: Paste from echo command (auto-sanitized)**
```yaml
csv_line: "echo 'flast,flast@redhat.com,DEVQE,First,Last,IBMC-devqe,DPP-00000' >> username-devqe.csv"
aap_template_names: ["Template1","Template2","Template3"]
```
The playbook automatically strips the `echo '...'` wrapper and `>> filename` redirection, leaving just the CSV data.

**Important:**
- The `csv_line` variable will automatically be passed to both the Twingate playbook and the AAP tasks. You only need to set it once in the job template extra variables - you do NOT need to set both `csv_line` and `twingate_csv_line`.
- The `aap_template_names` variable accepts both string (comma-separated) and list formats, so use whichever is most convenient for your setup.

Alternatively, you can use a CSV file by setting:
```yaml
csv_path: '/path/to/users.csv'
aap_template_names: 'Template1,Template2,Template3'
```

## Customization

### Custom CSV Path

Use a different CSV file:

```bash
ansible-playbook playbooks/main.yml \
  -e "csv_path=/path/to/your/users.csv" \
  -e "aap_template_names=Template1,Template2"
```

### Custom Twingate Subdomain

Override the subdomain at runtime:

```bash
ansible-playbook playbooks/twingate_create_users.yml \
  -e "twingate_subdomain=your-subdomain"
```

## Troubleshooting

### Verify Connectivity

Test Twingate API:
```bash
curl -H "X-API-KEY: $TWINGATE_API_KEY" \
  https://your-subdomain.twingate.com/api/graphql/
```

Test AAP connectivity:
```bash
curl -H "Authorization: Bearer $TOWER_OAUTH_TOKEN" \
  $TOWER_HOST/api/v2/ping/
```

### Verbose Output

Add `-v`, `-vv`, or `-vvv` for increasing verbosity:

```bash
ansible-playbook playbooks/main.yml -vv \
  -e "aap_template_names=Template1"
```

### Dry Run

Check syntax without making changes:

```bash
ansible-playbook playbooks/main.yml --syntax-check
ansible-playbook playbooks/main.yml --check
```

## Common Warnings

### AWX Collection Warning

You may see this warning when running the playbooks:
```
[WARNING]: You are using the awx version of this collection but connecting to Red Hat Ansible Automation Platform
```

**This is normal and can be safely ignored.** The `awx.awx` collection is fully compatible with Red Hat AAP. The warning is informational only - Red Hat prefers the `ansible.controller` collection for AAP, but it requires Red Hat Automation Hub access (subscription required).

To suppress this warning, uncomment the following line in `ansible.cfg`:
```ini
warnings_version = False
```

## Security Notes

- Never commit `.env` files or credentials to version control
- Use Ansible Vault for sensitive data in production
- Restrict API key permissions to minimum required
- Use token-based AAP authentication when possible
- Review and validate CSV data before processing

## Support

For issues or questions:
- Review playbook comments and inline documentation
- Check `CLAUDE.md` for development guidance
- Verify environment variables are properly set
- Test API connectivity independently
