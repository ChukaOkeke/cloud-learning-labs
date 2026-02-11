This project provisions an apache web server on a custom AWS VPC using Terraform, based on the following algorithm:
- Create a VPC
- Create Internet Gateway
- Create Custom Route Table
- Create a Subnet
- Associate the Route Table with the Subnet
- Create a Security Group to allow port 22, 80, and 443
- Create a network interface with an ip in the subnet that was created
- Assign an Elastic IP to the network interface that was created
- Create Ubuntu server and install/enable apache2