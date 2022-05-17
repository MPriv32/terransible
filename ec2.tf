data "aws_ami" "ec2_ami" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name = "name"

    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "random_id" "random_ec2_id" {
  byte_length = 2
  count       = var.main_instance_count
}

resource "aws_key_pair" "ec2_auth" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}
resource "aws_instance" "main_ec2" {
  count                  = var.main_instance_count
  instance_type          = var.main_instance_type
  ami                    = data.aws_ami.ec2_ami.id
  key_name               = aws_key_pair.ec2_auth.id
  # user_data              = templatefile("./main-userdata.tpl", { new_hostname = "EC2-main-${random_id.random_ec2_id[count.index].dec}" })
  vpc_security_group_ids = [aws_security_group.vpc_sg.id]
  subnet_id              = aws_subnet.public_subnet[count.index].id
  root_block_device {
    volume_size = var.main_vol_size
  }

  tags = {
    Name = "EC2-main-${random_id.random_ec2_id[count.index].dec}"
  }

  provisioner "local-exec" {
    # Linux version
    command = "printf '\n${self.public_ip}' >> aws_hosts && aws ec2 wait instance-status-ok --instance-ids ${self.id} --region us-west-2"

    #Powershell version
    # command     = "'${self.public_ip}' | Out-File -Encoding UTF8 -Append aws_hosts"
    # interpreter = ["Powershell", "-Command"]
  }

  provisioner "local-exec" {
    when        = destroy
    command = "sed -i '/^[0-9]/d' aws_hosts"

    #Powershell
    # command     = "@(Get-Content ./aws_hosts) -notmatch '^[0-9]' | Set-Content ./aws_hosts"
    # interpreter = ["Powershell", "-Command"]
  }

}

# resource "null_resource" "grafana_update" {
#   count = var.main_instance_count
#   provisioner "remote-exec" {
#     inline = ["sudo apt upgrade -y grafana && touch upgrade.log && echo 'I updated Grafana' >> upgrade.log"]

#     connection {
#       type        = "ssh"
#       user        = "ubuntu"
#       private_key = file("/home/mp32/.ssh/id_rsa")
#       host        = aws_instance.main_ec2[count.index].public_ip
#     }
#   }
# }

resource "null_resource" "grafana_install" {
  depends_on = [
    aws_instance.main_ec2
  ]
  provisioner "local-exec" {
    command = "ansible-playbook -i aws_hosts --key-file /home/ubuntu/.ssh/mtckey playbooks/main-playbook.yml"
  }
}

