#!/bin/bash
set -e

# Default values
RESOURCE_GROUP=""
TAG_NAME="toupgrade"
TAG_VALUE="true"
UPGRADE_TAG_NAME="upgraded"
UPGRADE_TAG_VALUE="true"

# Parse named parameters
for arg in "$@"; do
  case $arg in
    rg=*)
      RESOURCE_GROUP="${arg#*=}"
      ;;
    tag=*)
      TAG_NAME="${arg#*=}"
      ;;
    value=*)
      TAG_VALUE="${arg#*=}"
      ;;
    tagafter=*)
      UPGRADE_TAG_NAME="${arg#*=}"
      ;;
    valueafter=*)
      UPGRADE_TAG_VALUE="${arg#*=}"
      ;;
    *)
      echo "WARNING: Unknown parameter: $arg"
      ;;
  esac
done

# Verify required parameters
if [ -z "$RESOURCE_GROUP" ]; then
  echo "ERROR: Resource group name is required with the rg= parameter"
  echo "Usage: $0 rg=ResourceGroupName [tag=TagName] [value=TagValue] [tagafter=UpgradeTagName] [valueafter=UpgradeTagValue]"
  echo ""
  echo "Example: $0 rg=myResourceGroup tag=toupgrade value=true tagafter=upgraded valueafter=true"
  exit 1
fi

echo "Looking for VMs with tag $TAG_NAME=$TAG_VALUE in resource group $RESOURCE_GROUP..."

# Get all VMs with the specified tag
VM_LIST=$(az vm list -g $RESOURCE_GROUP --query "[?tags.$TAG_NAME=='$TAG_VALUE'].name" -o json)

# Count VMs found
VM_COUNT=$(echo $VM_LIST | jq '. | length')
echo "Found $VM_COUNT VMs with tag $TAG_NAME=$TAG_VALUE"

# Initialize counters
RUNNING_VMS=0
STOPPED_VMS=0
UPGRADED_VMS=0
SKIPPED_VMS=0
SKIPPED_NON_CANONICAL=0

# Process each VM without using a pipe to avoid subshell issues
VM_NAMES=($(echo "$VM_LIST" | jq -r '.[]'))

for VM_NAME in "${VM_NAMES[@]}"; do
  # Get VM power state
  POWER_STATE=$(az vm get-instance-view -g $RESOURCE_GROUP -n $VM_NAME --query "instanceView.statuses[?contains(code, 'PowerState')].displayStatus" -o tsv)
  
  echo "Processing VM: $VM_NAME (Power state: $POWER_STATE)"
  
  # Check if VM's image is from Canonical
  PUBLISHER=$(az vm get-instance-view -g $RESOURCE_GROUP -n $VM_NAME --query "storageProfile.imageReference.publisher" -o tsv 2>/dev/null || echo "unknown")
  
  echo "  Image publisher: $PUBLISHER"
  
  # Skip if not a Canonical image (case insensitive)
  if [[ "$(echo $PUBLISHER | tr '[:upper:]' '[:lower:]')" != "canonical" ]]; then
    echo "  VM is not using an Ubuntu image published by Canonical, skipping upgrade"
    SKIPPED_NON_CANONICAL=$((SKIPPED_NON_CANONICAL+1))
    SKIPPED_VMS=$((SKIPPED_VMS+1))
    continue
  fi
  
  # Check if VM is running
  if [[ "$POWER_STATE" == "VM running" ]]; then
    echo "  VM is running, proceeding with upgrade operations..."
    RUNNING_VMS=$((RUNNING_VMS+1))
    
    # Update the license type to UBUNTU_PRO
    echo "  Updating license type to UBUNTU_PRO..."
    az vm update -g $RESOURCE_GROUP -n $VM_NAME --license-type UBUNTU_PRO
    
    # Run the Ubuntu Pro client installation and activation
    echo "  Installing and activating Ubuntu Pro..."
    INSTALL_RESULT=$(az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME --command-id RunShellScript --scripts "sudo apt update && sudo apt install ubuntu-pro-client -y && sudo pro auto-attach")
    
    # Check if installation was successful
    if [ $? -eq 0 ]; then
      echo "  Ubuntu Pro client installation successful!"
      
      # Add the upgraded tag and remove the original upgrade tag
      echo "  Adding tag $UPGRADE_TAG_NAME=$UPGRADE_TAG_VALUE and removing tag $TAG_NAME..."
      
      # Get current tags
      CURRENT_TAGS=$(az vm show -g $RESOURCE_GROUP -n $VM_NAME --query tags -o json)
      
      # Remove the toupgrade tag from the JSON
      UPDATED_TAGS=$(echo $CURRENT_TAGS | jq "del(.$TAG_NAME)")
      
      # Add the upgraded tag
      UPDATED_TAGS=$(echo $UPDATED_TAGS | jq ". + {\"$UPGRADE_TAG_NAME\": \"$UPGRADE_TAG_VALUE\"}")
      
      # Apply the updated tags
      az vm update -g $RESOURCE_GROUP -n $VM_NAME --set tags="$UPDATED_TAGS"
      
      UPGRADED_VMS=$((UPGRADED_VMS+1))
      echo "  All operations completed successfully for $VM_NAME"
    else
      echo "  ERROR: Ubuntu Pro installation or activation failed on $VM_NAME"
      echo "  Tag not added since installation failed"
      echo "  Installation output: $INSTALL_RESULT"
    fi
  else
    echo "  VM is not running (state: $POWER_STATE), skipping upgrade operations"
    STOPPED_VMS=$((STOPPED_VMS+1))
    SKIPPED_VMS=$((SKIPPED_VMS+1))
  fi
done

# Show summary
echo ""
echo "===== UPGRADE SUMMARY ====="
echo "Total VMs found with tag $TAG_NAME=$TAG_VALUE: $VM_COUNT"
echo "Running VMs: $RUNNING_VMS"
echo "Stopped VMs: $STOPPED_VMS"
echo "VMs upgraded to Ubuntu Pro: $UPGRADED_VMS"
echo "VMs skipped: $SKIPPED_VMS"
echo "  - Non-Canonical images: $SKIPPED_NON_CANONICAL"
echo "  - Stopped VMs: $STOPPED_VMS"
echo "=========================="

if [ $SKIPPED_VMS -gt 0 ]; then
  echo ""
  echo "NOTE: Some VMs were skipped for the following reasons:"
  
  if [ $SKIPPED_NON_CANONICAL -gt 0 ]; then
    echo "- $SKIPPED_NON_CANONICAL VMs were not running Ubuntu images from Canonical"
  fi
  
  if [ $STOPPED_VMS -gt 0 ]; then
    echo "- $STOPPED_VMS VMs were not running"
    echo "  To upgrade these VMs, start them and run this script again."
  fi
fi 
