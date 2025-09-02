# Download AlmaLinux Generic Cloud image
resource "proxmox_virtual_environment_download_file" "nocloud_image" {
  content_type = "import"
  datastore_id = var.proxmox.download_datastore_id
  node_name    = var.proxmox.download_node_name
  file_name    = "almalinux-10-genericcloud-latest.qcow2"
  url          = "https://repo.almalinux.org/almalinux/10/cloud/x86_64_v2/images/AlmaLinux-10-GenericCloud-latest.x86_64_v2.qcow2"
  overwrite    = false
}

# Fetch SSH keys from GitHub
data "http" "github_keys" {
  url = "https://github.com/Myrenic.keys"
}

# Generate komodo password
resource "random_password" "komodo_app_password" {
  length           = 12
  override_special = "_%@"
  special          = true
}

# Generate komodo password
resource "random_password" "komodo_app_secret" {
  length           = 32
  special          = false
}

# Generate db password
resource "random_password" "mango_db_password" {
  length           = 12
  override_special = "_%@"
  special          = true
}

# Generate VM password
resource "random_password" "almalinux_vm_password" {
  length           = 12
  override_special = "_%@"
  special          = true
}

# VM resource
resource "proxmox_virtual_environment_vm" "vm" {
  for_each    = var.hosts
  name        = each.value.name
  description = var.proxmox.host_description
  tags        = var.proxmox.host_tags
  node_name   = each.value.node_name
  on_boot     = true

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  agent {
    enabled = true
    timeout = "30s" # sometimes the healthcheck takes a while, i'm impatient. DAISNAID
  }

  network_device {
    bridge  = each.value.network_bridge
    vlan_id = each.value.vlan_id
  }

  disk {
    datastore_id = each.value.datastore_id
    file_id      = proxmox_virtual_environment_download_file.nocloud_image.id
    file_format  = "qcow2"
    interface    = "virtio0"
    size         = each.value.disk_size
  }

  disk {
    datastore_id = each.value.hdd_datastore_id
    interface    = "virtio1"
    file_format  = "raw"
    size         = each.value.hdd_disk_size
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = each.value.datastore_id

    ip_config {
      ipv4 {
        address = "${each.value.ip_addr}${each.value.cidr}"
        gateway = each.value.gateway
      }
    }

    dns {
      servers = ["10.123.4.8", "10.123.4.9"] # Cloudflare + Google
      domain  = "emea.thermo.com"
    }

    user_account {
      username = "almalinux"
      password = random_password.almalinux_vm_password.result
      keys     = split("\n", chomp(data.http.github_keys.response_body))
    }
  }
}


resource "ansible_playbook" "deploy_komodo" {
  for_each = proxmox_virtual_environment_vm.vm

  name     = each.value.name
  playbook = "playbook.yml"

  extra_vars = {
    ansible_host                = split("/", each.value.initialization[0].ip_config[0].ipv4[0].address)[0]
    ansible_user                = "almalinux"
    ansible_private_key_file    = "~/.ssh/mtuntelder_admin"
    ansible_ssh_extra_args   = "-o StrictHostKeyChecking=no"
    mongo_user                  = "admin"
    mongo_password              = random_password.mango_db_password.result
    komodo_user                 = "tfs.admin"
    komodo_password             = random_password.komodo_app_password.result
    komodo_secret_key           = random_password.komodo_app_secret.result
  }

  replayable = true
}
output "vm_debug" {
  value = proxmox_virtual_environment_vm.vm
  sensitive = true
}
output "almalinux_vm_password" {
  value     = random_password.almalinux_vm_password.result
  sensitive = true
}

output "komodo_app_secret" {
  value     = random_password.komodo_app_secret.result
  sensitive = true
}

output "komodo_app_user" {
  value     = "tfs.admin"
  sensitive = true
}

output "komodo_app_password" {
  value     = random_password.komodo_app_password.result
  sensitive = true
}

output "mango_db_password" {
  value     = random_password.mango_db_password.result
  sensitive = true
}