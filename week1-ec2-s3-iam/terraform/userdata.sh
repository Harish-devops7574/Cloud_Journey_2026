#!/bin/bash
yum update -y
yum install httpd -y
systemctl start httpd
systemctl enable httpd
echo '<h1>Hello from Harish EC2 via Terraform</h1>' > /var/www/html/index.html

yum install cronie -y
systemctl start crond
systemctl enable crond

cat > /home/ec2-user/cloud_automate.sh << 'SCRIPT'
#!/bin/bash
echo "Log generated at $(date)" >> /tmp/app.log
aws s3 cp /tmp/app.log s3://harish-aws-lab-bucket-tf/logs/app.log
SCRIPT

chmod +x /home/ec2-user/cloud_automate.sh
echo '* * * * * /bin/bash /home/ec2-user/cloud_automate.sh >> /tmp/cron.log 2>&1' | crontab -
