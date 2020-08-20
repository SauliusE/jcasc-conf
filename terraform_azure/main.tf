provider "azurerm" {
  version = "~>2.0"
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "jcasc-rg"
  location = "North Europe"
  tags = {
    Environment = "dev"
    Project     = "jcasc-demo"
  }
}

resource "azurerm_virtual_network" "network" {
  name                = "jcasc-network"
  location            = "North Europe"
  address_space       = ["10.0.0.0/16"]
  resource_group_name = azurerm_resource_group.rg.name
  tags = {
    Environment = "dev"
    Project     = "jcasc-demo"
  }
}

resource "azurerm_subnet" "subnet" {
  name                 = "jcasc-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.network.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "public-ip" {
  name                = "jcasc-public-ip"
  location            = "North Europe"
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  tags = {
    Environment = "dev"
    Project     = "jcasc-demo"
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = "jacasc-nsg"
  location            = "North Europe"
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "213.212.16.66"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "HTTP"
    description                = "Jenkins master HTTP port"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "213.212.16.66"
    destination_address_prefix = "*"
  }
  tags = {
    Environment = "dev"
    Project     = "jcasc-demo"
  }
}

resource "azurerm_network_interface" "vnic" {
  name                = "jcasc-nic"
  location            = "North Europe"
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "jcasc-nic-configuration"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public-ip.id
  }
  tags = {
    Environment = "dev"
    Project     = "jcasc-demo"
  }
}

resource "azurerm_network_interface_security_group_association" "nic-sg" {
  network_interface_id      = azurerm_network_interface.vnic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "random_id" "randomId" {
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = azurerm_resource_group.rg.name
  }

  byte_length = 8
}

resource "azurerm_storage_account" "storage" {
  name                     = "diag${random_id.randomId.hex}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = "North Europe"
  account_replication_type = "LRS"
  account_tier             = "Standard"

  tags = {
    Environment = "dev"
    Project     = "jcasc-demo"
  }
}

resource "tls_private_key" "jcasc-ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

#output "tls_private_key" {
#    value = tls_private_key.jcasc-ssh.private_key_pem
#}

resource "local_file" "private-key" {
  content         = tls_private_key.jcasc-ssh.private_key_pem
  filename        = "${path.module}/jcasc_id_rsa"
  file_permission = "0600"
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "jcasc-vm"
  location              = "North Europe"
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.vnic.id]
  size                  = "Standard_B1s"

  os_disk {
    name                 = "jcasc-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.7"
    version   = "latest"
  }

  computer_name                   = "jcasc-vm"
  admin_username                  = "jcascadmin"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "jcascadmin"
    public_key = tls_private_key.jcasc-ssh.public_key_openssh
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.storage.primary_blob_endpoint
  }
  tags = {
    Environment = "dev"
    Project     = "jcasc-demo"
  }
}

# Make sure VM is up and running and ready to accept ssh connections
resource "null_resource" "ssh-check" {
  connection {
    type        = "ssh"
    user        = azurerm_linux_virtual_machine.vm.admin_username
    host        = azurerm_public_ip.public-ip.ip_address
    private_key = tls_private_key.jcasc-ssh.private_key_pem
  }
  provisioner "remote-exec" {
    inline = ["echo 'Ready to work!'"]
  }
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ${azurerm_public_ip.public-ip.ip_address}, --private-key jcasc_id_rsa -u jcascadmin ../ansible/jcasc-playbook.yml"
  }
}

