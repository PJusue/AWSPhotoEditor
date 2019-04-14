#!/bin/bash
apt-get upgrade -y
apt-get update -y
apt-get install apache2 -y
apt-get install git -y
apt-get install python3 -y
apt-get install python3-pip -y
pip install Pillow
apt-get install mysql-client -y
python3 -m pip install Pillow
pip3 install boto3
pip3 install mysql-connector
pip3 install flask
git clone git@github.com:illinoistech-itm/pjusue.git /home/ubuntu/pjusue
chown -R ubuntu:ubuntu /home/ubuntu/*
cd /home/ubuntu/pjusue/ITMO-544/MP3/pythonPrograms
python3 imageprocessor.py
#cp pjusue/ITMO-544/MP1/index.html /var/www/html
#while [ ! -e /dev/xvdf ]
#do
#sleep 2
#done
#mkfs.ext4 /dev/xvdf
#mkdir /mnt/datadisk
#mount /dev/xvdf /mnt/datadisk/
