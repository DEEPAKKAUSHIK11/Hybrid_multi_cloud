

provider "aws" {
    profile="deepak"
    region="ap-south-1"
}


//creating AMI_ID
variable  "ami_id" {
  type =string
  default = "ami-005956c5f0f757d37"
}

//creating AMI_TYPE
variable "ami_type" {
  type =string
  default = "t2.micro"
}

//creating key
resource "tls_private_key" "tls_key" {
algorithm = "RSA"
}

//generating key_value_pair
resource "aws_key_pair" "generated_key" {
key_name ="web-envi-key"
public_key ="${tls_private_key.tls_key.public_key_openssh}"
depends_on =[tls_private_key.tls_key]
}

//saving private key pem file
resource "local_file" "key-file" {
content ="${tls_private_key.tls_key.private_key_pem}"
filename ="web-envi-key.pem"
depends_on =[tls_private_key.tls_key]
}

//creating security group

resource  "aws_security_group"  "web-SG" {
name        = "Web-envi-SG"
description = "Web enviornment security group"

 
ingress {

description = "SSH rule"
from_port   = 22
to_port     = 22
protocol    = "tcp"
cidr_blocks = ["0.0.0.0/0"]
     }

     ingress {
description = "HTTP rule"
from_port   = 80
to_port     = 80
protocol    = "tcp"
cidr_blocks = ["0.0.0.0/0"]
     }
}



//creating s3 bucket
resource "aws_s3_bucket" "kaushik-bucket" {
  bucket = "deepak1234-bucket"
  acl    = "public-read"

  tags = {
    Name        = "kaushik-bucket"
  }
}


//putting object in s3 bucket
resource "aws_s3_bucket_object"  "web-object1" {
bucket ="${aws_s3_bucket.kaushik-bucket.bucket}"
key    ="kohli.jfif"
source ="C:/Users/deepak/Desktop/kohli.jfif"
acl    ="public-read"
}

//creating cloudfront with s3 bucket origin
resource "aws_cloudfront_distribution"  "s3-web-distribution" {
origin {
  domain_name ="${aws_s3_bucket.kaushik-bucket.bucket_regional_domain_name}"
  origin_id ="${aws_s3_bucket.kaushik-bucket.id}"
}
        enabled = true
is_ipv6_enabled = true
comment = "s3 web distribution"

default_cache_behavior {
   allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
cached_methods = ["GET", "HEAD"]
target_origin_id = "${aws_s3_bucket.kaushik-bucket.id}"

forwarded_values {
query_string =false
  cookies {
forward ="none"
  }
}
viewer_protocol_policy = "allow-all"
min_ttl = 0
default_ttl =3600
max_ttl =86400
}
restrictions {
 geo_restriction {
restriction_type = "whitelist"
locations = ["IN"]
}

}
tags = {
  Name = "web-CF-disrtibution"
  Environment  ="production"
}

viewer_certificate {
cloudfront_default_certificate = true
}
depends_on =[aws_s3_bucket.kaushik-bucket]
}


// Launching ec2 instance
resource "aws_instance" "web" {
  ami             = "${var.ami_id}"
  instance_type   = "${var.ami_type}"
  key_name        = "${aws_key_pair.generated_key.key_name}"
  security_groups = ["${aws_security_group.web-SG.name}","default"]

  //Labelling the Instance
  tags = {
    Name = "Web-Env"
    env  = "Production"
  } 

  depends_on = [
    aws_security_group.web-SG,
    aws_key_pair.generated_key
  ]
}

resource "null_resource" "remote1" {
  
  depends_on = [ aws_instance.web, ]
  //Executing Commands to initiate WebServer in Instance Over SSH 
  provisioner "remote-exec" {
    connection {
      agent       = "false"
      type        = "ssh"
      user        = "ec2-user"
      private_key = "${tls_private_key.tls_key.private_key_pem}"
      host        = "${aws_instance.web.public_ip}"
    }
    
    inline = [
      "sudo yum install httpd git -y",
      "sudo service httpd start ",
      "sudo service httpd enable"
    ]

}

}
//Creating EBS Volume
resource "aws_ebs_volume" "web-vol" {
  availability_zone = "${aws_instance.web.availability_zone}"
  size              = 1
  
  tags = {
    Name = "ebs-vol"
  }
}


//Attaching EBS Volume to a Instance
resource "aws_volume_attachment" "ebs_att" {
  device_name  = "/dev/sdh"
  volume_id    = "${aws_ebs_volume.web-vol.id}"
  instance_id  = "${aws_instance.web.id}"
  force_detach = true 


  provisioner "remote-exec" {
    connection {
      agent       = "false"
      type        = "ssh"
      user        = "ec2-user"
      private_key = "${tls_private_key.tls_key.private_key_pem}"
      host        = "${aws_instance.web.public_ip}"
    }
    
    inline = [
      "sudo mkfs.ext4 /dev/sdh",
      "sudo mount /dev/sdh /var/www/html/",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/DEEPAKKAUSHIK11/Hybrid_multi_cloud.git /var/www/html/",
    ]
  }


  depends_on = [
    aws_instance.web,
    aws_ebs_volume.web-vol
  ]
}
