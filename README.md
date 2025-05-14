# Azure Ubuntu Pro Upgrade Script

This script automates the process of upgrading Ubuntu VMs in Azure to Ubuntu Pro. It finds VMs with a specific tag, updates their license type, installs the Ubuntu Pro client, and activates it.

## Features

- Finds VMs in a resource group with a specific tag (default: `toupgrade=true`)
- Verifies VM is running before attempting upgrade
- Verifies VM is using a Canonical image
- Updates the VM license type to Ubuntu Pro
- Installs and activates Ubuntu Pro on the VM
- Removes the original tag and adds a new tag after successful upgrade (default: `upgraded=true`)
- Provides a detailed summary of processed and skipped VMs

## Usage

```bash
./upgrade-script.sh rg=ResourceGroupName [tag=TagName] [value=TagValue] [tagafter=UpgradeTagName] [valueafter=UpgradeTagValue]
```

### Parameters

- `rg`: (Required) The Azure resource group containing the VMs
- `tag`: (Optional) The tag name to identify VMs for upgrade (default: "toupgrade")
- `value`: (Optional) The tag value to identify VMs for upgrade (default: "true")
- `tagafter`: (Optional) The tag name to apply after successful upgrade (default: "upgraded")
- `valueafter`: (Optional) The tag value to apply after successful upgrade (default: "true")

### Example

```bash
./upgrade-script.sh rg=myResourceGroup tag=toupgrade value=true tagafter=upgraded valueafter=true
```

## Requirements

- Azure CLI (`az` command) must be installed and authenticated
- jq must be installed for JSON processing
- The user running the script must have permissions to:
  - List VMs in the resource group
  - Update VM properties
  - Run commands on VMs
  - Apply tags to resources

## Limitations

- Only operates on running VMs (skips powered off VMs)
- Only processes Ubuntu VMs from Canonical (skips other images)
- Requires the target VM to have network connectivity 