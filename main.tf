provider "aws"{
    region = "ap-south-1"
}

#vpc
resource "aws_vpc" "main_vpc" {
    cidr_block = "10.0.0.0/16"
    tags = {
      "Name" = "test_vpc"
    }
}
#public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id = aws_vpc.main_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = {
    "Name" = "test_public_subnet"
  }
}

#private subnet 1
resource "aws_subnet" "private_subnet1" {
    vpc_id = aws_vpc.main_vpc.id
    cidr_block = "10.0.2.0/24"
    availability_zone = "ap-south-1a"
    tags = {
     "Name" = "test_private_subnet1"
   }
}

#private subnet 2
resource "aws_subnet" "private_subnet2" {
  vpc_id = aws_vpc.main_vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "ap-south-1b"
  tags = {
    "Name" = "test_private_subnet2"
  }
}

#Internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
}

#Route table for public subnet
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id
  route  {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Route Table Association for Public Subnet
resource "aws_route_table_association" "public_assoc" {
    route_table_id = aws_route_table.public_route_table.id
    subnet_id = aws_subnet.public_subnet.id
}

# NACL for Public Subnet
resource "aws_network_acl" "public_nacl" {
  vpc_id = aws_vpc.main_vpc.id
  # Allow inbound traffic for HTTP, SSH, and all traffic for ephemeral ports
  ingress  {
    protocol = "tcp"
    rule_no = 100
    action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port = 80
    to_port = 80
  }
  ingress {
    protocol = "tcp"
    rule_no = 101
    action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port = 22
    to_port = 22
  }
  ingress {
    protocol = "tcp"
    rule_no = 102
    action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port = 1024
    to_port = 65535
  }
  # Allow outbound traffic for all ports
  egress {
    protocol = "-1"
    rule_no = 100
    action = "allow"
    cidr_block = "0.0.0.0/0"
    from_port = 0
    to_port = 0
  }
}
# Associate NACL with Public Subnet
resource "aws_network_acl_association" "public_nacl_assoc" {
    subnet_id = aws_subnet.public_subnet.id
    network_acl_id = aws_network_acl.public_nacl.id
}

# NACL for Private Subnets
resource "aws_network_acl" "private_nacl" {
  vpc_id = aws_vpc.main_vpc.id
  # Inbound Rules (allow RDS and EC2 traffic)
  ingress {
    protocol = "tcp"
    rule_no = 100
    action = "allow"
    cidr_block = "10.0.0.0/16"
    from_port  = 3306
    to_port    = 3306
  }
  egress {
    protocol = "-1"
    rule_no = 100
    action = "allow"
    cidr_block = "10.0.0.0/16"
    from_port  = 0
    to_port    = 0
  }
}

# Associate NACL with Private Subnet 1
resource "aws_network_acl_association" "private1_nacl_assoc" {
    network_acl_id = aws_network_acl.private_nacl.id
    subnet_id = aws_subnet.private_subnet1.id
}

# Associate NACL with Private Subnet 2
resource "aws_network_acl_association" "private2_nacl_assoc" {
    network_acl_id = aws_network_acl.private_nacl.id
    subnet_id = aws_subnet.private_subnet2.id
}

# RDS Subnet Group (Private Subnets)
resource "aws_db_subnet_group" "rds_subnet_group" {
    name = "rds_subnet_group"
    subnet_ids = [ aws_subnet.private_subnet1.id, aws_subnet.private_subnet2.id ]
}

resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.main_vpc.id
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Ami datasource
data "aws_ami" "ubuntu" {
  most_recent = true
  owners  = ["099720109477"] # Canonical (Ubuntu) owner ID
  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name = "architecture"
    values = [ "x86_64" ]
  }
  filter {
    name = "root-device-type"
    values = ["ebs"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 Instance in Public Subnet
resource "aws_instance" "ec2_instance_pub" {
    tags = {
        Name = "HelloWorld"
    }
    ami = data.aws_ami.ubuntu.id
    instance_type = "t2.micro"
    subnet_id = aws_subnet.public_subnet.id
    security_groups = [ aws_security_group.ec2_sg.id ]
    associate_public_ip_address = true
     key_name  = "product-ec2-key-pair" 
}
# Security Group for RDS
resource "aws_security_group" "rds_sg" {
    vpc_id = aws_vpc.main_vpc.id
    ingress {
        from_port = 3306
        to_port = 3306
        protocol = "tcp"
        cidr_blocks = ["10.0.0.0/16"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# RDS Instance
resource "aws_db_instance" "rds_instance" {
    allocated_storage = 20
    db_name              = "mydb"
    engine               = "mysql"
    engine_version       = "8.0"
    instance_class       = "db.t3.micro"
    username  = "admin"
    password  = "welcome1"
    db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.id
    vpc_security_group_ids = [ aws_security_group.rds_sg.id ]
    skip_final_snapshot = true
    # Disable automatic backups
   backup_retention_period = 0
}