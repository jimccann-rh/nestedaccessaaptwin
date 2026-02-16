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

### Two-Stage Workflow

The project uses a master orchestration approach:

1. **Stage 1 (Twingate)**: `twingate_create_users.yml` reads CSV, creates users via GraphQL API (uses email addresses from column 2)
2. **Stage 2 (AAP)**: Extracts usernames from same CSV, grants AAP template access to each user (uses kerberos IDs from column 1)

**Important:** Twingate uses **email addresses** while AAP uses **usernames/kerberos IDs**. The CSV format accommodates both:
- Column 1: Username (kerberos ID) - used for AAP
- Column 2: Email address - used for Twingate

This is implemented in `playbooks/main.yml` which imports the Twingate playbook and then runs AAP tasks in batch mode.

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

**Key Distinction:**
- Twingate API requires email addresses to create users
- AAP requires kerberos IDs/usernames to grant permissions
- The CSV contains both in columns 1 and 2 respectively

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

### CSV Format Handling

**Headerless CSV (default):**
The project uses headerless CSV by default. Format: `username,email,DEVQE,First,Last,GroupName,DPP-00000`

**Inline CSV Line:**
You can pass a single CSV line via `-e csv_line='...'` instead of using a file. This is useful for:
- Processing individual users
- Integration with other systems or scripts
- Testing without creating a file

Both `twingate_create_users.yml` and `main.yml` support this via the `csv_line` variable. When provided, the CSV file is ignored.

**CSV with Headers:**
If you need to support CSV with headers:
1. Set `twingate_csv_headerless: false` in `vars/twingate_defaults.yml`
2. Ensure CSV has `Email` column (and optionally `Group` or `GroupName`)
3. Update `tasks/twingate/load_users.yml` logic

### Error Handling

Both integrations use `assert` tasks to validate inputs:
- Twingate: Validates API key is set
- AAP: Validates template names and username are provided

Tasks will fail early with clear messages if requirements aren't met.

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

**Overridable via `-e`:**
- `csv_path` - Path to user CSV file (default: `data/usernames-devqe.csv`)
- `csv_line` - Single CSV line to process instead of file (e.g., `'flast,flast@redhat.com,DEVQE,First,Last,IBMC-devqe,DPP-00000'`)
- `twingate_subdomain` - Twingate subdomain
- `aap_template_names` - Comma-separated AAP template names
- `template_name` / `template_names` - For standalone AAP playbook
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
