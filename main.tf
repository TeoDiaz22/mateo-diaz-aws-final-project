provider "aws" {
    shared_config_files = ["~/.aws/config"]
    shared_credentials_files = ["~/.aws/credentials"]
}

resource "aws_vpc" "fis_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "FIS VPC"
  }
}

resource "aws_subnet" "public_subnet" {
  cidr_block = "10.0.1.0/24"
  vpc_id = aws_vpc.fis_vpc.id
  tags = {
    Name = "Public Subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  cidr_block = "10.0.2.0/24"
  vpc_id = aws_vpc.fis_vpc.id
  tags = {
    Name = "Private Subnet"
  }
}

resource "aws_internet_gateway" "fis_public_internet_gateway" {
  vpc_id = aws_vpc.fis_vpc.id
  tags = {
    Name = "FIS public internet gateway"
  }
}

resource "aws_route_table" "fis_public_subnet_route_table" {
  vpc_id = aws_vpc.fis_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.fis_public_internet_gateway.id
    }

    route {
        ipv6_cidr_block = "::/0"
        gateway_id = aws_internet_gateway.fis_public_internet_gateway.id
    }

    tags = {
      Name = "FIS public subnet route table"
    }
}

resource "aws_route_table_association" "fis_public_association" {
  route_table_id = aws_route_table.fis_public_subnet_route_table.id
  subnet_id = aws_subnet.public_subnet.id
}

resource "aws_security_group" "web_server_sg" {
  vpc_id = aws_vpc.fis_vpc.id

  ingress {
    description = "Allow HTTP trafic from internet"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]       
  }

  ingress {
    description = "Allow HTTPS trafic from internet"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all trafic"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  } 

  tags = {
    Name = "AEIS security group"
  }          
}

//Data Block , Specific information for a resource
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name = "name"
    values = [ "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*" ]
  }

  filter {
    name = "virtualization-type"
    values = [ "hvm" ]
  }

  owners = [ "099720109477" ]
}


resource "aws_network_interface" "aeis_network_interface" {
  subnet_id = aws_subnet.public_subnet.id
  private_ips = ["10.0.1.23"]    
  security_groups = [aws_security_group.web_server_sg.id]
  tags = {
    Name = "AEIS network interface"
  }
}

resource "aws_eip" "aeis_ip" {
  associate_with_private_ip = tolist(aws_network_interface.aeis_network_interface.private_ips)[0]
  network_interface = aws_network_interface.aeis_network_interface.id
  instance = aws_instance.ubuntu_aeis_instance.id
  tags = {
    Name = "AEIS elasticIP"
  }
}

resource "aws_instance" "ubuntu_aeis_instance" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  network_interface {
    network_interface_id = aws_network_interface.aeis_network_interface.id
    device_index = 0
  }
  user_data = <<-EOF
              #!bin/bash
              sudo apt update -y
              sudo apt install nginx -y
              sudo systemctl start nginx
              EOF
  tags = {
    Name = "Ubuntu AEIS instance"
  }
}

output "public_aeis_ip" {
  value = aws_eip.aeis_ip.public_ip
}

output "private_aeis_ip" {
  value = aws_eip.aeis_ip.private_ip
}

