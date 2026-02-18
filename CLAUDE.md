# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a combined Ansible automation project that orchestrates user provisioning across two systems:

1. **Twingate** - Zero trust network access platform. Creates users via GraphQL API and assigns them to groups.
2. **AAP (Ansible Automation Platform)** - Grants job template execute permissions to users via the awx.awx collection.

The typical workflow: provision users in Twingate first, then grant them AAP template access.

## Common Commands

### Installation and Setup

```bash
# Install required collections
ansible-galaxy collection install -r requirements.yml

# Set up environment variables
cp .env.example .env
# Edit .env with actual credentials
source .env
```

### Running the Complete Workflow

```bash
# Run both Twingate user creation and AAP access granting
ansible-playbook playbooks/main.yml \
  -e "aap_template_names=Template1,Template2"

# With custom CSV file
ansible-playbook playbooks/main.yml \
  -e "csv_path={{ playbook_dir }}/../data/custom-users.csv" \
  -e "aap_template_names=Template1,Template2"
```

### Running Individual Components

```bash
# Twingate only - create users from CSV file
ansible-playbook playbooks/twingate_create_users.yml

# Twingate only - create user from inline CSV line
ansible-playbook playbooks/twingate_create_users.yml \
  -e 'csv_line=flast,flast@redhat.com,DEVQE,First,Last,IBMC-devqe,DPP-00000'

# AAP only - grant access to single user (use kerberos ID, not email)
ansible-playbook playbooks/aap_grant_access.yml \
  -e "username=flast" \
  -e "template_name=MyTemplate"

# AAP - grant access to multiple templates
ansible-playbook playbooks/aap_grant_access.yml \
  -e "username=flast" \
  -e "template_names=Template1,Template2,Template3"
```

### Using Tags

```bash
# Run only Twingate tasks
ansible-playbook playbooks/main.yml --tags twingate

# Run only AAP tasks
ansible-playbook playbooks/main.yml --tags aap \
  -e "aap_template_names=Template1,Template2"

# Enable Jira ticket closure (disabled by default)
ansible-playbook playbooks/main.yml \
  -e "jira_enabled=true" \
  -e "aap_template_names=Template1,Template2"

# Skip Jira ticket closure (can also just omit jira_enabled=true)
ansible-playbook playbooks/main.yml --skip-tags jira \
  -e "aap_template_names=Template1,Template2"

# Run only Jira tasks (requires CSV with successful provisioning and jira_enabled=true)
ansible-playbook playbooks/main.yml --tags jira \
  -e "jira_enabled=true"
```

### Testing and Validation

```bash
# Syntax check
ansible-playbook playbooks/main.yml --syntax-check

# Dry run (check mode)
ansible-playbook playbooks/main.yml --check \
  -e "aap_template_names=Template1"

# Verbose output for debugging
ansible-playbook playbooks/main.yml -vv \
  -e "aap_template_names=Template1"
```

## Architecture

### Three-Stage Workflow

The project uses a master orchestration approach:

1. **Stage 1 (Twingate)**: `twingate_create_users.yml` reads CSV, creates users via GraphQL API (uses email addresses from column 2)
2. **Stage 2 (AAP)**: Extracts usernames from same CSV, grants AAP template access to each user (uses kerberos IDs from column 1)
3. **Stage 3 (Jira - Optional)**: After successful completion of both stages, automatically closes Jira tickets (ticket IDs from column 7)

**Important:** Twingate uses **email addresses** while AAP uses **usernames/kerberos IDs**. The CSV format accommodates both:
- Column 1: Username (kerberos ID) - used for AAP
- Column 2: Email address - used for Twingate
- Column 7: Jira ticket ID (e.g., DPP-00000) - used for automatic ticket closure (optional)

This is implemented in `playbooks/main.yml` which imports the Twingate playbook and then runs AAP tasks in batch mode.

**Variable Passthrough:**
The playbooks are designed to accept variables from `-e` command-line arguments or AAP job extra variables:
- `csv_line` - Passed from `main.yml` to `twingate_create_users.yml` automatically
- `csv_path` - Can be overridden at any level
- `aap_template_names` - Used by `main.yml` for AAP tasks

Important: Both `main.yml` and `twingate_create_users.yml` do NOT define default values for `csv_line` and `aap_template_names` in their vars sections. This allows these variables to be passed through from `-e` arguments or AAP job configuration without being shadowed by hardcoded defaults. All conditions use `| default('')` to handle undefined variables gracefully.

This design ensures that when running on AAP, you only need to set `csv_line` once via extra variables, and it will be available to both the Twingate playbook and the AAP tasks.

### Configuration Management

**Environment-based Configuration:**
- All sensitive credentials (API keys, tokens) come from environment variables
- `TWINGATE_API_KEY` - Required for Twingate operations
- `TOWER_HOST`, `TOWER_OAUTH_TOKEN` (or `TOWER_USERNAME`/`TOWER_PASSWORD`) - Required for AAP operations

**Configuration Files:**
- `inventory/group_vars/all.yml` - AAP controller settings (read from env vars)
- `vars/twingate_defaults.yml` - Twingate API settings (subdomain, GraphQL queries)
- `.env.example` - Template for environment variables

**Running as AAP Job:**
When running these playbooks as AAP jobs (not just targeting AAP, but executing within AAP), both Twingate and AAP credentials are automatically injected:

**Twingate API Key (Custom Credential):**
- Create a Custom Credential Type in AAP for Twingate API key
- The credential should inject the API key as `custom_token` variable
- The Twingate playbook will automatically use `custom_token` if available
- No code changes needed - the playbook checks for `custom_token` automatically

**AAP/Tower Credentials (Built-in Credential Type):**
- Attach a "Red Hat Ansible Automation Platform" credential to your Job Template
- AAP automatically injects: `host`, `username`, `password`, `oauth_token`, `verify_ssl`
- `inventory/group_vars/all.yml` automatically detects and uses these variables
- No extra configuration needed - just attach the credential to the job template

Credential Loading Priority (in `inventory/group_vars/all.yml`):
1. AAP credential injection: `host`, `username`, `password`, `oauth_token`, `verify_ssl` (for AAP job execution)
2. Environment variables: `TOWER_HOST`, `TOWER_USERNAME`, `TOWER_PASSWORD`, `TOWER_OAUTH_TOKEN`, `TOWER_VERIFY_SSL` (for local CLI runs)
3. Default values (fallback)

API Key Loading Priority (in `playbooks/twingate_create_users.yml`):
1. Environment variable `TWINGATE_API_KEY` (for local CLI runs)
2. AAP custom credential `custom_token` (for AAP job execution)
3. `.env` file fallback (for local runs without env export)

To configure in AAP:
1. **Twingate API Key:**
   - Create Custom Credential Type with input: `custom_token`
   - Create a Credential using that type with your Twingate API key
   - Attach to your Job Template
2. **AAP/Tower Credentials:**
   - Create or use existing "Red Hat Ansible Automation Platform" credential
   - Set the target AAP instance URL, username/token, etc.
   - Attach to your Job Template
3. AAP will inject all variables automatically when the job runs

### Twingate Integration

**API Approach:**
- Uses GraphQL API at `https://<subdomain>.twingate.com/api/graphql/`
- Authentication via `X-API-KEY` header
- Tasks are in `tasks/twingate/` directory

**Key Tasks:**
- `load_users.yml` - Reads CSV (headerless format: col2=email, col6=group)
- `build_group_map.yml` - Fetches all Twingate groups, creates name→ID mapping
- `fetch_all_users.yml` - Fetches existing users (paginated) to avoid duplicates
- `create_users.yml` - Orchestrates user creation loop
- `create_one_user.yml` - Creates single user via GraphQL mutation, adds to group

**CSV Format:**
Headerless CSV with format: `username,email,DEVQE,First,Last,GroupName,DPP-00000`
- Column 1 (index 0): Username/Kerberos ID - used for AAP access grants
- Column 2 (index 1): Email address - used for Twingate user creation
- Column 6 (index 5): Twingate group name - optional

### AAP Integration

**Module Used:**
- `awx.awx.role` module from the `awx.awx` collection
- Assigns `execute` role on job templates to users
- Note: `awx.awx` works with both AWX and Red Hat AAP. For official Red Hat AAP deployments, `ansible.controller` is preferred but requires Red Hat Automation Hub access

**Playbooks:**
- `aap_grant_access.yml` - Standalone playbook for single user
- `aap_grant_access_task.yml` - Task file called in loop from `main.yml`

**Authentication:**
Supports two methods (configured in `inventory/group_vars/all.yml`):
1. Token-based (recommended): `controller_oauthtoken`
2. Username/password: `controller_username` + `controller_password`

### Data Flow

1. CSV file (`data/usernames-devqe.csv`) is the single source of truth
2. Twingate playbook reads CSV → extracts emails (column 2) → creates users + assigns groups
3. AAP batch task reads same CSV → extracts usernames (column 1) → grants template access to each
4. Jira post-tasks (optional) reads same CSV → extracts ticket IDs (column 7) → closes tickets with comments

**Key Distinction:**
- Twingate API requires email addresses to create users
- AAP requires kerberos IDs/usernames to grant permissions
- Jira integration uses ticket IDs to close provisioning requests
- The CSV contains all three data points in columns 1, 2, and 7 respectively

## Development Guidelines

### Adding New Twingate Operations

Twingate tasks use GraphQL queries/mutations defined in `vars/twingate_defaults.yml`:
- `twingate_query_groups` - List groups (paginated)
- `twingate_query_users` - List users (paginated)
- `twingate_mutation_user_create` - Create user
- `twingate_mutation_group_update` - Add user to group

When adding new operations, follow the existing pattern:
1. Define query/mutation in `vars/twingate_defaults.yml`
2. Create task file in `tasks/twingate/`
3. Use `ansible.builtin.uri` module with `twingate_headers` and `twingate_graphql_url`

### Adding New AAP Operations

The AAP integration uses the `awx.awx` collection modules. Common modules:
- `awx.awx.role` - Manage role assignments (used for execute permissions)
- `awx.awx.job_template` - Manage templates
- `awx.awx.job_launch` - Launch jobs

All use the controller authentication variables from `inventory/group_vars/all.yml`.

**Note:** The warning "You are using the awx version of this collection but connecting to Red Hat Ansible Automation Platform" is informational only. The `awx.awx` collection is fully compatible with AAP.

### Jira Integration

**Overview:**
The project can automatically close Jira tickets after successful user provisioning. This is an **optional feature disabled by default** that runs after both Twingate and AAP tasks complete successfully.

**Enabling Jira Integration:**
Jira integration must be explicitly enabled using the `jira_enabled` variable:
```bash
ansible-playbook playbooks/main.yml \
  -e "jira_enabled=true" \
  -e "aap_template_names=Template1,Template2"
```

**How It Works:**
- Must be enabled with `-e "jira_enabled=true"` (defaults to `false`)
- Extracts Jira ticket IDs from CSV (column 7, e.g., DPP-00000)
- After both Twingate user creation AND AAP access grant succeed, the playbook:
  1. Adds a comment to the Jira ticket documenting the provisioning
  2. Transitions the ticket to a closed state (searches for transitions named "Close", "Done", or "Resolve")
- Uses Jira REST API v2 with API token authentication
- Ticket closure runs in `post_tasks` section of `main.yml`

**Authentication:**
Supports two authentication methods with flexible credential sources:

**Credential Priority (highest to lowest):**
1. Command-line extra vars: `-e jira_pat=...` or `-e jira_email=... -e jira_api_token=...`
2. Environment variables: `JIRA_PAT` or `JIRA_EMAIL` + `JIRA_API_TOKEN`
3. AAP custom credentials: `jira_pat_credential` or `jira_email_credential` + `jira_api_token_credential`

**Authentication Methods:**

1. **Personal Access Token (PAT) - RECOMMENDED** for Red Hat Jira / Jira Data Center:
   - Command line: `-e "jira_pat=your_token"`
   - Environment variable: Set `JIRA_PAT`
   - AAP job execution: Use AAP custom credential that injects `jira_pat_credential`
   - Simpler and more secure - only one credential needed
   - **To get a PAT for Red Hat Jira:**
     - Go to https://issues.redhat.com
     - Click your profile → Personal Access Tokens
     - Click "Create token"
     - Copy and use the token

2. **Email + API Token** (fallback) for Jira Cloud or if PAT not available:
   - Command line: `-e "jira_email=..." -e "jira_api_token=..."`
   - Environment variables: Set `JIRA_EMAIL` and `JIRA_API_TOKEN`
   - AAP job execution: Use AAP custom credential that injects `jira_email_credential` and `jira_api_token_credential`
   - **To get an API token for Jira Cloud:**
     - Go to https://id.atlassian.com/manage-profile/security/api-tokens
     - Click "Create API token"
     - Copy and use the token

Base URL: Defaults to `https://issues.redhat.com`, override with `JIRA_BASE_URL` or `-e "jira_base_url=..."`

**Note:** If PAT is provided (via any method), it will be used and email+token will be ignored.

**Error Handling:**
- Jira integration uses "warn and continue" approach
- If `jira_enabled=false` (default), all Jira tasks are skipped
- If `jira_enabled=true` but credentials are not set, Jira tasks are skipped (no error)
- If ticket update fails, a warning is logged but the playbook continues
- User provisioning success is not dependent on Jira ticket closure

**Disabling Jira Integration:**
Jira integration is disabled by default. To ensure it's disabled:
- Omit the `-e "jira_enabled=true"` flag (default behavior)
- Or explicitly set: `-e "jira_enabled=false"`
- Or use tags: `ansible-playbook playbooks/main.yml --skip-tags jira`

**AAP Job Configuration:**
When running as AAP jobs, choose one authentication method:

**Option 1: PAT via secret (Recommended for existing AAP credentials)**
If you already have a custom credential type that injects `secret`:
1. Attach your existing credential to the Job Template
2. In your Job Template's extra variables, add: `jira_enabled: true`
3. AAP will automatically use `secret` as the Jira PAT
4. No code changes needed - the playbook automatically detects `secret`

**Option 2: PAT via jira_pat_credential (Alternative)**
1. Create a Custom Credential Type with input: `jira_pat_credential`
2. Create a Credential using that type with your Jira PAT
3. Attach to your Job Template
4. In your Job Template's extra variables, add: `jira_enabled: true`
5. AAP will inject the credential variable automatically when the job runs

**Option 3: Email + API Token (Fallback)**
1. Create a Custom Credential Type with inputs: `jira_email_credential`, `jira_api_token_credential`
2. Create a Credential using that type with your Jira email and API token
3. Attach to your Job Template
4. In your Job Template's extra variables, add: `jira_enabled: true`
5. AAP will inject the credential variables automatically when the job runs

**Task Files:**
- `tasks/jira/close_ticket.yml` - Main Jira ticket closure task
  - Adds comment with provisioning details
  - Fetches available transitions
  - Finds and executes close/done/resolve transition
  - Reports success or failure

### CSV Format Handling

**Headerless CSV (default):**
The project uses headerless CSV by default. Format: `username,email,DEVQE,First,Last,GroupName,DPP-00000`

**Inline CSV Line:**
You can pass a single CSV line via `-e csv_line='...'` instead of using a file. This is useful for:
- Processing individual users
- Integration with other systems or scripts
- Testing without creating a file

Both `twingate_create_users.yml` and `main.yml` support this via the `csv_line` variable. When provided, the CSV file is ignored.

**Auto-sanitization:**
The playbooks automatically strip common shell command wrappers from `csv_line`, allowing you to paste commands directly from scripts:
- Detects: `echo 'data' >> filename` or `echo "data" > filename`
- Extracts: Just the CSV data between quotes
- Example: Input `echo 'flast,flast@redhat.com,...' >> file.csv` → Output `flast,flast@redhat.com,...`
- Implementation: Uses `regex_replace` to remove `echo`, quotes, and redirection operators
- Only sanitizes if the pattern is detected (doesn't affect normal CSV input)

**Input Validation:**
The playbooks now validate CSV input before processing:
- If `csv_line` is provided, it takes priority (CSV file is ignored)
- If `csv_line` is not provided, the playbook checks if the CSV file exists
- If neither exists, the playbook fails with a clear error message explaining both input options
- This prevents confusing file-not-found errors during task execution

**CSV with Headers:**
If you need to support CSV with headers:
1. Set `twingate_csv_headerless: false` in `vars/twingate_defaults.yml`
2. Ensure CSV has `Email` column (and optionally `Group` or `GroupName`)
3. Update `tasks/twingate/load_users.yml` logic

### Error Handling

The playbooks use `assert` tasks to validate inputs and fail early with clear messages:

**Twingate Validation:**
- API key is set (checks environment variable, AAP custom credential, or .env file)
- CSV input exists (either file or inline data)

**AAP Validation:**
- Template names are provided
- Username is provided (for standalone playbook)
- CSV input exists for batch operations (either file or inline data)

**Jira Validation:**
- Jira integration is optional - tasks are skipped if credentials are not set
- No errors are raised if Jira is not configured
- If Jira update fails, a warning is logged but playbook continues
- This ensures user provisioning succeeds even if Jira ticket closure fails

**CSV Input Validation:**
Both `twingate_create_users.yml` and `main.yml` check for CSV input before processing:
1. If inline CSV data (`csv_line`) is provided, use it
2. If not, check if the CSV file exists using `ansible.builtin.stat`
3. If neither exists, fail with a message showing both input options

This prevents confusing errors during task execution and guides users to provide input correctly.

## File Organization

```
playbooks/
  main.yml                     - Master orchestration (imports twingate, runs AAP batch)
  twingate_create_users.yml    - Twingate user creation from CSV
  aap_grant_access.yml         - AAP access for single user (standalone)
  aap_grant_access_task.yml    - AAP access task (called in loop)

tasks/twingate/                - All Twingate GraphQL operations
  create_users.yml             - Main user creation orchestrator
  create_one_user.yml          - Single user creation + group assignment
  load_users.yml               - CSV parsing
  build_group_map.yml          - Fetch groups, create name→ID map
  fetch_all_users.yml          - Fetch existing users (pagination)
  list_groups.yml              - List groups operation

tasks/jira/                    - Jira integration tasks
  close_ticket.yml             - Close Jira ticket with comment

vars/
  twingate_defaults.yml        - Twingate config (subdomain, GraphQL queries)

inventory/group_vars/
  all.yml                      - AAP controller connection variables

data/
  usernames-devqe.csv          - Default user input file
```

## Environment Variables Reference

**Required:**
- `TWINGATE_API_KEY` - Twingate API key (for local CLI runs)
- `TOWER_HOST` - AAP instance URL
- `TOWER_OAUTH_TOKEN` - AAP auth token (or use username/password below)

**Optional:**
- `TOWER_USERNAME` / `TOWER_PASSWORD` - Alternative to token auth
- `TOWER_VERIFY_SSL` - SSL verification (default: true)
- `JIRA_PAT` - Jira Personal Access Token (preferred for Red Hat Jira / Jira Data Center)
- `JIRA_EMAIL` - Email for Jira API authentication (fallback method, for Jira Cloud)
- `JIRA_API_TOKEN` - Jira API token (required if JIRA_EMAIL is set, fallback method)
- `JIRA_BASE_URL` - Jira instance URL (default: https://issues.redhat.com)

**Note:** For Jira authentication, set either `JIRA_PAT` (preferred) OR `JIRA_EMAIL` + `JIRA_API_TOKEN`. If both are set, PAT takes priority.

**AAP Job Execution:**

When running as AAP jobs, these variables are injected automatically by AAP credentials:

*Twingate (via custom credential):*
- `custom_token` - Twingate API key (injected via AAP custom credential)
  - Not set manually - AAP injects this automatically when you attach the custom credential
  - The playbook will use this if `TWINGATE_API_KEY` is not available

*AAP/Tower (via built-in "Red Hat Ansible Automation Platform" credential):*
- `host` - AAP instance URL (used instead of `TOWER_HOST`)
- `username` - AAP username (used instead of `TOWER_USERNAME`)
- `password` - AAP password (used instead of `TOWER_PASSWORD`)
- `oauth_token` - AAP OAuth token (used instead of `TOWER_OAUTH_TOKEN`)
- `verify_ssl` - SSL verification setting (used instead of `TOWER_VERIFY_SSL`)
- Not set manually - AAP injects these automatically when you attach an AAP credential
- `inventory/group_vars/all.yml` automatically uses these if environment variables are not available

*Jira (via custom credential - optional):*
- **Most Preferred:** `secret` - Jira Personal Access Token (injected via AAP custom credential)
  - Used if you have an existing credential type that injects `secret`
  - Automatically detected and used as Jira PAT
  - No custom credential type creation needed if this already exists
- **Preferred:** `jira_pat_credential` - Jira Personal Access Token (injected via AAP custom credential)
  - Used for Red Hat Jira / Jira Data Center
  - Simpler - only one credential needed
  - Used if `secret` is not available
- **Fallback:** `jira_email_credential` + `jira_api_token_credential` - Email and API token (injected via AAP custom credential)
  - Used for Jira Cloud or if PAT not available
- Not set manually - AAP injects these automatically when you attach the Jira custom credential
- The playbook checks for credentials in order: `secret` → `jira_pat_credential` → `jira_email_credential` + `jira_api_token_credential`
- **Important:** Even with credentials set, you must also enable Jira with `jira_enabled: true` in job template extra variables
- If `jira_enabled=false` (default), Jira integration is skipped regardless of credentials

**Overridable via `-e`:**
- `csv_path` - Path to user CSV file (default: `data/usernames-devqe.csv`)
- `csv_line` - Single CSV line to process instead of file (e.g., `'flast,flast@redhat.com,DEVQE,First,Last,IBMC-devqe,DPP-00000'`)
- `jira_enabled` - Enable Jira ticket closure (default: `false`, set to `true` to enable)
- `jira_pat` - Jira Personal Access Token (overrides environment variable and AAP credential)
- `jira_email` - Jira email for API authentication (overrides environment variable and AAP credential)
- `jira_api_token` - Jira API token (overrides environment variable and AAP credential)
- `jira_base_url` - Jira base URL (default: `https://issues.redhat.com`)
- `twingate_subdomain` - Twingate subdomain
- `aap_template_names` - AAP template names (comma-separated string OR YAML list)
  - String format: `'Template1,Template2,Template3'`
  - List format: `["Template1","Template2","Template3"]` or YAML list
- `template_name` / `template_names` - For standalone AAP playbook (same format options)
- `username` - For standalone AAP playbook (kerberos ID, not email)

**Note:** When `csv_line` is provided, `csv_path` is ignored. This is useful for processing single users or integrating with other systems.

## Common Patterns

### Sequential Playbook Import
`main.yml` uses `import_playbook` to run Twingate first, then defines AAP tasks inline. This ensures Twingate users exist before granting AAP access.

### Paginated GraphQL Queries
Twingate tasks use recursive includes for pagination:
- `list_groups.yml` calls `list_groups_page.yml` recursively
- `fetch_all_users.yml` calls `fetch_users_page.yml` recursively
- Each page task checks `pageInfo.hasNextPage` and recurses with `endCursor`

### CSV Email Extraction
The AAP batch task extracts emails using Jinja2 filters:
```yaml
user_emails: "{{ lookup('file', csv_path).split('\n') |
                map('split', ',') |
                map('extract', [1]) |
                select('match', '.*@.*') |
                list }}"
```
This splits on newlines, splits each line on commas, extracts column 2, filters for emails.

### Loop Variable Naming
The AAP batch uses `loop_control: loop_var: user_email` to avoid conflicts when including tasks that have their own loops.
