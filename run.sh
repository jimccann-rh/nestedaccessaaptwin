#!/bin/bash
# Quick start script for Twingate + AAP user provisioning
#
# Usage:
#   ./run.sh setup                        - Install dependencies
#   ./run.sh full [templates]             - Run complete workflow (uses default DEVQE templates if not specified)
#   ./run.sh twingate                     - Run Twingate only
#   ./run.sh aap <username> <template(s)> - Run AAP only (username = kerberos ID)
#
# Examples:
#   ./run.sh setup
#   ./run.sh full                         # Uses default DEVQE templates
#   ./run.sh full "Template1,Template2"   # Custom templates
#   ./run.sh twingate
#   ./run.sh aap flast "MyTemplate"
#   ./run.sh aap flast "Template1,Template2,Template3"

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if .env exists and load it
if [ -f .env ]; then
    echo -e "${GREEN}Loading environment from .env${NC}"
    set -a  # Automatically export all variables
    source .env
    set +a  # Stop auto-exporting
else
    echo -e "${YELLOW}Warning: .env file not found. Using environment variables.${NC}"
fi

case "$1" in
    setup)
        echo -e "${GREEN}Installing Ansible collection dependencies...${NC}"
        ansible-galaxy collection install -r requirements.yml
        echo -e "${GREEN}Setup complete!${NC}"
        ;;

    full)
        # Default templates for DEVQE
        DEFAULT_TEMPLATES="vSphere-Nested-DEVQE,vSphere-Nested-DEVQE-static,vSphere-Nested-DEVQE-static-autoscript,vSphere-Nested-DEVQE-vSAN,vSphere-Nested-DEVQE-vSphere-9,vSphere-Nested-DEVQE-vSphere-9-static,vSphere-Nested-DEVQE-vSphere-9-static-autoscript,vSphere-Nested-DEVQE-vSAN-vsphere-9"

        TEMPLATES="${2:-$DEFAULT_TEMPLATES}"

        echo -e "${GREEN}Running complete workflow: Twingate + AAP${NC}"
        echo -e "${YELLOW}Templates: $TEMPLATES${NC}"
        ansible-playbook playbooks/main.yml \
            -e "aap_template_names=$TEMPLATES"
        ;;

    twingate)
        echo -e "${GREEN}Running Twingate user creation only${NC}"
        ansible-playbook playbooks/twingate_create_users.yml
        ;;

    aap)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo -e "${RED}Error: Please provide username (kerberos ID) and template name(s)${NC}"
            echo "Usage: ./run.sh aap username \"TemplateName\""
            echo "       ./run.sh aap username \"Template1,Template2,Template3\""
            exit 1
        fi

        # Check if multiple templates (contains comma)
        if [[ "$3" == *,* ]]; then
            echo -e "${GREEN}Granting AAP access for $2 on multiple templates${NC}"
            ansible-playbook playbooks/aap_grant_access.yml \
                -e "username=$2" \
                -e "template_names=$3"
        else
            echo -e "${GREEN}Granting AAP access for $2 on $3${NC}"
            ansible-playbook playbooks/aap_grant_access.yml \
                -e "username=$2" \
                -e "template_name=$3"
        fi
        ;;

    *)
        echo "Twingate + AAP User Provisioning"
        echo ""
        echo "Usage:"
        echo "  ./run.sh setup                        - Install dependencies"
        echo "  ./run.sh full [templates]             - Run complete workflow"
        echo "  ./run.sh twingate                     - Run Twingate only"
        echo "  ./run.sh aap <username> <template(s)> - Run AAP only (username = kerberos ID)"
        echo ""
        echo "Examples:"
        echo "  ./run.sh setup"
        echo "  ./run.sh full                         # Uses default DEVQE templates"
        echo "  ./run.sh full \"Template1,Template2\"   # Custom templates"
        echo "  ./run.sh twingate"
        echo "  ./run.sh aap flast \"MyTemplate\""
        echo "  ./run.sh aap flast \"Template1,Template2,Template3\""
        echo ""
        echo "Default templates: vSphere-Nested-DEVQE, vSphere-Nested-DEVQE-static,"
        echo "  vSphere-Nested-DEVQE-static-autoscript, vSphere-Nested-DEVQE-vSAN,"
        echo "  vSphere-Nested-DEVQE-vSphere-9, vSphere-Nested-DEVQE-vSphere-9-static,"
        echo "  vSphere-Nested-DEVQE-vSphere-9-static-autoscript, vSphere-Nested-DEVQE-vSAN-vsphere-9"
        exit 1
        ;;
esac
